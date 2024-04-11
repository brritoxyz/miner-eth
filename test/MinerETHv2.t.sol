// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {FlywheelCore} from "flywheel-v2/FlywheelCore.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IRouter} from "src/interfaces/IRouter.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {IRewardsDistributor} from "test/interfaces/IRewardsDistributor.sol";
import {IBrrETHv2} from "src/interfaces/IBrrETHv2.sol";
import {MinerETHv2} from "src/MinerETHv2.sol";
import {MinerETHv2Factory} from "src/MinerETHv2Factory.sol";
import {IMoonwellHelper} from "test/interfaces/IMoonwellHelper.sol";
import {IMWETH} from "test/interfaces/IMWETH.sol";

contract MinerETHv2Test is Test {
    using LibString for string;
    using SafeTransferLib for address;

    IBrrETHv2 public constant BRR_ETH_V2 =
        IBrrETHv2(0xD729A94d6366a4fEac4A6869C8b3573cEe4701A9);
    address public constant BRR_ETH_V2_HELPER =
        0xeDB5625634C5Bee920a1054712FDB8F6ae53218e;
    IMoonwellHelper public constant MOONWELL_HELPER =
        IMoonwellHelper(0x7ea675e183e753d9e5f2b833b9c014727A4Ca57A);
    IWETH public constant WETH =
        IWETH(0x4200000000000000000000000000000000000006);
    address public constant MWETH = 0x628ff693426583D9a7FB391E54366292F509D457;
    address public constant ELON = 0xAa6Cccdce193698D33deb9ffd4be74eAa74c4898;
    IRouter public constant ROUTER =
        IRouter(0xe88483B5901FA3537355C4324ccF92a8d4155260);
    uint256 public constant MOONWELL_SLIPPAGE = 1e9;
    string public constant TOKEN_NAME = "Brrito Miner V2-ETH/ElonRWA";
    string public constant TOKEN_SYMBOL = "brrMINERv2-ETH/ElonRWA";
    uint256 public constant TOKEN_DECIMALS = 18;
    uint256 public constant DEAD_SHARES_VALUE = 0.01 ether;
    MinerETHv2Factory public immutable factory = new MinerETHv2Factory();
    MinerETHv2 public immutable miner;
    IRewardsDistributor public immutable rewardsDistributor;
    address public immutable dynamicRewards;
    address public immutable rewardsStore;

    receive() external payable {}

    constructor() {
        miner = MinerETHv2(payable(factory.deploy(ELON)));
        rewardsDistributor = IRewardsDistributor(
            address(miner.rewardsDistributor())
        );
        dynamicRewards = address(rewardsDistributor.flywheelRewards());
        rewardsStore = miner.rewardsStore();

        assertEq(TOKEN_NAME, miner.name());
        assertEq(TOKEN_SYMBOL, miner.symbol());

        deal(address(this), 1_000 ether);

        miner.deposit{value: 0.01 ether}("");
    }

    function _calculateSharesFromDeposit(
        uint256 assets
    ) private view returns (uint256) {
        return
            BRR_ETH_V2.convertToShares(
                // Convert ETH to MWETH before converting to brrETHv2.
                MOONWELL_HELPER.calculateDeposit(MWETH, assets)
            );
    }

    function _calculateAssetsFromRedeem(
        uint256 shares
    ) private view returns (uint256) {
        return
            // Convert brrETHv2 to MWETH before converting to ETH.
            MOONWELL_HELPER.calculateRedeem(
                MWETH,
                BRR_ETH_V2.convertToAssets(shares)
            );
    }

    function _getEstimates()
        private
        view
        returns (
            uint256 estimatedRedepositShares,
            uint256 estimatedInterest,
            uint256 estimatedRewards,
            uint256 estimatedStrategyIndex,
            uint256 estimatedRewardsAccrued
        )
    {
        uint256 minerTotalSupply = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH_V2.balanceOf(address(miner));
        (uint256 strategyIndex, ) = rewardsDistributor.strategyState(
            SolmateERC20(address(miner))
        );
        uint256 redeemedAssets = _calculateAssetsFromRedeem(minerSharesBalance);
        estimatedRedepositShares = _calculateSharesFromDeposit(
            // Deposit available balance if less than total supply and vice versa.
            redeemedAssets < minerTotalSupply
                ? redeemedAssets
                : minerTotalSupply
        );
        estimatedInterest = redeemedAssets > minerTotalSupply
            ? redeemedAssets - minerTotalSupply
            : 0;

        if (estimatedInterest != 0)
            (, estimatedRewards) = ROUTER.getSwapOutput(
                keccak256(abi.encodePacked(address(WETH), ELON)),
                estimatedInterest
            );
        estimatedStrategyIndex =
            ((estimatedRewards * 1e18) / minerTotalSupply) +
            strategyIndex;
        uint256 userIndex = rewardsDistributor.userIndex(
            SolmateERC20(address(miner)),
            address(this)
        );
        uint256 deltaIndex = estimatedStrategyIndex - userIndex;
        uint256 userTokens = miner.balanceOf(address(this));
        uint256 userDelta = (userTokens * deltaIndex) / 1e18;
        estimatedRewardsAccrued =
            rewardsDistributor.rewardsAccrued(address(this)) +
            userDelta;
    }

    /*//////////////////////////////////////////////////////////////
                            name
    //////////////////////////////////////////////////////////////*/

    function testName() external {
        assertEq(TOKEN_NAME, miner.name());
    }

    /*//////////////////////////////////////////////////////////////
                            symbol
    //////////////////////////////////////////////////////////////*/

    function testSymbol() external {
        assertEq(TOKEN_SYMBOL, miner.symbol());
    }

    /*//////////////////////////////////////////////////////////////
                            decimals
    //////////////////////////////////////////////////////////////*/

    function testDecimals() external {
        assertEq(TOKEN_DECIMALS, miner.decimals());
    }

    /*//////////////////////////////////////////////////////////////
                            mine
    //////////////////////////////////////////////////////////////*/

    function testMineZeroTotalSupply() external {
        MinerETHv2 newMiner = MinerETHv2(
            payable(factory.deploy(address(WETH)))
        );

        assertEq(0, newMiner.totalSupply());

        (uint256 interest, uint256 rewards) = newMiner.mine();

        assertEq(0, interest);
        assertEq(0, rewards);
    }

    function testMineWithCometDeficit() external {
        miner.mine();

        uint256 sharesBefore = BRR_ETH_V2.balanceOf(address(miner));
        uint256 assetsBefore = BRR_ETH_V2.convertToAssets(sharesBefore);

        // Calling mine multiple times in the same block will lead to less shares, less assets.
        // As of this writing, 500 iterations exceeds the 60M block gas limit.
        for (uint256 i = 0; i < 500; ++i) {
            miner.mine();
        }

        uint256 sharesAfter = BRR_ETH_V2.balanceOf(address(miner));
        uint256 assetsAfter = BRR_ETH_V2.convertToAssets(sharesAfter);

        assertLe(sharesAfter, sharesBefore);
        assertLe(assetsAfter, assetsBefore);

        skip(1);

        uint256 assetsAfterInterestAccrual = BRR_ETH_V2.convertToAssets(
            BRR_ETH_V2.balanceOf(address(miner))
        );

        // The interest accrued from the initial deposit, in a single block, will exceed the rounding losses
        // resulting from 500 iterations of calling `mine`.
        assertLe(assetsAfter, assetsAfterInterestAccrual);
    }

    function testMine() external {
        // Forward a block to accrue interest.
        vm.roll(block.number + 1);

        // Harvesting before calling `mine` makes it easier for us to calculate expected values.
        BRR_ETH_V2.harvest();

        uint256 minerTotalSupply = miner.totalSupply();
        uint256 dynamicRewardsBalance = ELON.balanceOf(dynamicRewards);
        (
            uint256 estimatedRedepositShares,
            uint256 estimatedInterest,
            uint256 estimatedRewards,
            uint256 estimatedStrategyIndex,
            uint256 estimatedRewardsAccrued
        ) = _getEstimates();
        (uint256 interest, uint256 rewards) = miner.mine();
        (
            uint256 strategyIndex,
            uint256 lastUpdatedTimestamp
        ) = rewardsDistributor.strategyState(SolmateERC20(address(miner)));
        uint256 rewardsAccrued = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        // Invariant.
        assertEq(minerTotalSupply, miner.totalSupply());
        assertEq(
            dynamicRewardsBalance + rewards,
            ELON.balanceOf(dynamicRewards)
        );
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertEq(0, address(WETH).balanceOf(address(miner)));
        assertEq(0, ELON.balanceOf(address(miner)));
        assertLt(0, interest);
        assertLt(0, rewards);
        assertLt(0, strategyIndex);
        assertLt(0, rewardsAccrued);

        // Estimates.
        assertLe(
            estimatedRedepositShares,
            BRR_ETH_V2.balanceOf(address(miner))
        );
        assertLe(estimatedInterest, interest);
        assertLe(estimatedRewards, rewards);
        assertLe(estimatedStrategyIndex, strategyIndex);
        assertLe(estimatedRewardsAccrued, rewardsAccrued);
    }

    function testMineFuzz(uint256 skipSeconds) external {
        skipSeconds = bound(skipSeconds, 1, 1_000);

        // Forward timestamp to accrue interest.
        skip(skipSeconds);

        // Harvesting before calling `mine` makes it easier for us to calculate expected values.
        BRR_ETH_V2.harvest();

        uint256 minerTotalSupply = miner.totalSupply();
        uint256 dynamicRewardsBalance = ELON.balanceOf(dynamicRewards);
        (
            uint256 estimatedRedepositShares,
            uint256 estimatedInterest,
            uint256 estimatedRewards,
            uint256 estimatedStrategyIndex,
            uint256 estimatedRewardsAccrued
        ) = _getEstimates();
        (uint256 interest, uint256 rewards) = miner.mine();
        (
            uint256 strategyIndex,
            uint256 lastUpdatedTimestamp
        ) = rewardsDistributor.strategyState(SolmateERC20(address(miner)));
        uint256 rewardsAccrued = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        // Invariant.
        assertEq(minerTotalSupply, miner.totalSupply());
        assertEq(
            dynamicRewardsBalance + rewards,
            ELON.balanceOf(dynamicRewards)
        );
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertEq(0, address(WETH).balanceOf(address(miner)));
        assertEq(0, ELON.balanceOf(address(miner)));
        assertLt(0, interest);
        assertLt(0, rewards);
        assertLt(0, strategyIndex);
        assertLt(0, rewardsAccrued);

        // Estimates.
        assertLe(
            estimatedRedepositShares,
            BRR_ETH_V2.balanceOf(address(miner))
        );
        assertLe(estimatedInterest, interest);
        assertLe(estimatedRewards, rewards);
        assertLe(estimatedStrategyIndex, strategyIndex);
        assertLe(estimatedRewardsAccrued, rewardsAccrued);
    }

    /*//////////////////////////////////////////////////////////////
                            deposit
    //////////////////////////////////////////////////////////////*/

    function testCannotDepositInvalidAmount() external {
        uint256 amount = 0;
        string memory memo = "test";

        vm.expectRevert(MinerETHv2.InvalidAmount.selector);

        miner.deposit{value: amount}(memo);
    }

    function testDeposit() external {
        BRR_ETH_V2.harvest();

        uint256 amount = 1 ether;

        deal(address(this), amount);

        string memory memo = "test";
        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupplyBefore = miner.totalSupply();
        (
            ,
            ,
            uint256 estimatedRewards,
            uint256 estimatedStrategyIndex,
            uint256 estimatedRewardsAccrued
        ) = _getEstimates();
        uint256 dynamicRewardsBalance = ELON.balanceOf(dynamicRewards);

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETHv2.Deposit(address(this), memo.packOne(), amount);

        miner.deposit{value: amount}(memo);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH_V2.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter -
            MOONWELL_SLIPPAGE;
        (uint256 strategyIndex, ) = rewardsDistributor.strategyState(
            SolmateERC20(address(miner))
        );
        uint256 rewardsAccrued = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        // Invariant.
        assertEq(tokenBalanceBefore + amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupplyBefore + amount, minerTotalSupplyAfter);
        assertLt(
            // The difference betweeen the principal and fully-redeemed assets should be less than the slippage.
            minerTotalSupplyAfter -
                _calculateAssetsFromRedeem(minerSharesBalance),
            MOONWELL_SLIPPAGE
        );
        assertLt(0, minerTotalSupplyAfter);
        assertLt(0, minerSharesBalance);
        assertLt(0, principalWithSlippage);
        assertLt(0, estimatedRewards);
        assertLt(0, estimatedStrategyIndex);
        assertLt(0, estimatedRewardsAccrued);

        // Estimates.
        assertLe(
            principalWithSlippage,
            _calculateAssetsFromRedeem(minerSharesBalance)
        );
        assertLe(
            estimatedRewards + dynamicRewardsBalance,
            ELON.balanceOf(dynamicRewards)
        );
        assertLe(estimatedStrategyIndex, strategyIndex);
        assertLe(estimatedRewardsAccrued, rewardsAccrued);
    }

    function testDepositFuzz(uint256 amount, string calldata memo) external {
        amount = bound(amount, 1e9, 1_000 ether);

        deal(address(this), amount);

        BRR_ETH_V2.harvest();

        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupplyBefore = miner.totalSupply();
        (
            uint256 estimatedRedepositShares,
            ,
            uint256 estimatedRewards,
            ,

        ) = _getEstimates();
        uint256 newShares = _calculateSharesFromDeposit(amount);
        uint256 dynamicRewardsBalance = ELON.balanceOf(dynamicRewards);

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETHv2.Deposit(address(this), memo.packOne(), amount);

        miner.deposit{value: amount}(memo);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH_V2.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter -
            MOONWELL_SLIPPAGE;

        // Invariant.
        assertEq(tokenBalanceBefore + amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupplyBefore + amount, minerTotalSupplyAfter);
        assertLt(
            minerTotalSupplyAfter -
                _calculateAssetsFromRedeem(minerSharesBalance),
            MOONWELL_SLIPPAGE
        );
        assertLt(0, minerTotalSupplyAfter);
        assertLt(0, minerSharesBalance);
        assertLt(0, principalWithSlippage);
        assertLt(0, estimatedRedepositShares);
        assertLt(0, estimatedRewards);

        // Estimates.
        assertLe(
            principalWithSlippage,
            _calculateAssetsFromRedeem(minerSharesBalance)
        );
        assertLe(
            estimatedRewards + dynamicRewardsBalance,
            ELON.balanceOf(dynamicRewards)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            withdraw
    //////////////////////////////////////////////////////////////*/

    function testCannotWithdrawInvalidAmount() external {
        uint256 amount = 0;

        vm.expectRevert(MinerETHv2.InvalidAmount.selector);

        miner.withdraw(amount);
    }

    function testWithdraw() external {
        uint256 amount = 1 ether;

        miner.deposit{value: amount}("");

        skip(1);

        BRR_ETH_V2.harvest();

        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();
        (
            uint256 estimatedRedepositShares,
            ,
            uint256 estimatedRewards,
            ,

        ) = _getEstimates();
        uint256 removedShares = BRR_ETH_V2.convertToShares(
            amount + MOONWELL_SLIPPAGE
        );
        uint256 rewardsAccruedBefore = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETHv2.Withdraw(address(this), amount);

        miner.withdraw(amount);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH_V2.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter -
            MOONWELL_SLIPPAGE;
        uint256 rewardsAccruedAfter = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        // Invariant.
        assertEq(tokenBalanceBefore - amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupply - amount, minerTotalSupplyAfter);
        assertLt(0, minerTotalSupplyAfter);
        assertLt(0, minerSharesBalance);
        assertLt(0, principalWithSlippage);
        assertLt(0, estimatedRedepositShares);
        assertLt(0, estimatedRewards);

        // Estimates.
        assertLe(
            principalWithSlippage,
            BRR_ETH_V2.convertToAssets(minerSharesBalance)
        );
        assertLe(estimatedRedepositShares - removedShares, minerSharesBalance);
        assertLe(estimatedRewards + rewardsAccruedBefore, rewardsAccruedAfter);
    }

    function testWithdrawFuzz(uint256 amount, uint256 skipSeconds) external {
        amount = bound(amount, 1e2, 1_000 ether);
        skipSeconds = bound(skipSeconds, 1, 365 days);

        deal(address(this), amount);

        miner.deposit{value: amount}("");

        skip(skipSeconds);

        BRR_ETH_V2.harvest();

        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();
        (
            uint256 estimatedRedepositShares,
            ,
            uint256 estimatedRewards,
            ,

        ) = _getEstimates();
        uint256 removedShares = BRR_ETH_V2.convertToShares(
            amount + MOONWELL_SLIPPAGE
        );
        uint256 rewardsAccruedBefore = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETHv2.Withdraw(address(this), amount);

        miner.withdraw(amount);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH_V2.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter -
            MOONWELL_SLIPPAGE;
        uint256 rewardsAccruedAfter = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        // Invariant.
        assertEq(tokenBalanceBefore - amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupply - amount, minerTotalSupplyAfter);
        assertLt(0, minerTotalSupplyAfter);
        assertLt(0, minerSharesBalance);
        assertLt(0, principalWithSlippage);
        assertLt(0, estimatedRedepositShares);
        assertLt(0, estimatedRewards);

        // Estimates.
        assertLe(
            principalWithSlippage,
            BRR_ETH_V2.convertToAssets(minerSharesBalance)
        );
        assertLe(estimatedRedepositShares - removedShares, minerSharesBalance);
        assertLe(estimatedRewards + rewardsAccruedBefore, rewardsAccruedAfter);
    }

    function testWithdrawPartialFuzz(
        uint256 amount,
        uint256 skipSeconds,
        uint256 withdrawalDivisor
    ) external {
        amount = bound(amount, 1e3, 1_000 ether);
        skipSeconds = bound(skipSeconds, 1, 365 days);
        withdrawalDivisor = bound(withdrawalDivisor, 1, type(uint8).max);

        deal(address(this), amount);

        miner.deposit{value: amount}("");

        skip(skipSeconds);

        BRR_ETH_V2.harvest();

        uint256 withdrawalAmount = amount / withdrawalDivisor;
        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();
        (
            uint256 estimatedRedepositShares,
            ,
            uint256 estimatedRewards,
            ,

        ) = _getEstimates();
        uint256 removedShares = BRR_ETH_V2.convertToShares(
            amount + MOONWELL_SLIPPAGE
        );
        uint256 rewardsAccruedBefore = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETHv2.Withdraw(address(this), withdrawalAmount);

        miner.withdraw(withdrawalAmount);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH_V2.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter -
            MOONWELL_SLIPPAGE;
        uint256 rewardsAccruedAfter = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        // Invariant.
        assertEq(
            tokenBalanceBefore - withdrawalAmount,
            miner.balanceOf(address(this))
        );
        assertEq(minerTotalSupply - withdrawalAmount, minerTotalSupplyAfter);
        assertLt(0, minerTotalSupplyAfter);
        assertLt(0, minerSharesBalance);
        assertLt(0, principalWithSlippage);
        assertLt(0, estimatedRedepositShares);
        assertLt(0, estimatedRewards);

        // Estimates.
        assertLe(
            principalWithSlippage,
            BRR_ETH_V2.convertToAssets(minerSharesBalance)
        );
        assertLe(estimatedRedepositShares - removedShares, minerSharesBalance);
        assertLe(estimatedRewards + rewardsAccruedBefore, rewardsAccruedAfter);
    }

    /*//////////////////////////////////////////////////////////////
                            claimRewards
    //////////////////////////////////////////////////////////////*/

    function testClaimRewards() external {
        uint256 amount = 1 ether;

        miner.deposit{value: amount}("");

        skip(1);

        miner.mine();

        uint256 rewardsAccrued = rewardsDistributor.rewardsAccrued(
            address(this)
        );
        uint256 elonBalanceBefore = ELON.balanceOf(address(this));
        uint256 dynamicRewardsBalanceBefore = ELON.balanceOf(dynamicRewards);

        vm.expectEmit(true, true, true, false, address(miner));

        emit MinerETHv2.ClaimRewards(address(this), rewardsAccrued);

        uint256 rewards = miner.claimRewards();
        uint256 rewardsAccruedAfter = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        assertEq(0, rewardsAccruedAfter);
        assertEq(elonBalanceBefore + rewards, ELON.balanceOf(address(this)));
        assertLe(
            dynamicRewardsBalanceBefore - rewards,
            ELON.balanceOf(dynamicRewards)
        );
        assertLe(rewardsAccrued, rewards);
    }

    function testClaimRewardsFuzz(
        uint256 amount,
        uint256 skipSeconds
    ) external {
        amount = bound(amount, 1e2, 1_000 ether);
        skipSeconds = bound(skipSeconds, 1, 365 days);

        deal(address(this), amount);

        miner.deposit{value: amount}("");

        skip(skipSeconds);

        miner.mine();

        uint256 rewardsAccrued = rewardsDistributor.rewardsAccrued(
            address(this)
        );
        uint256 elonBalanceBefore = ELON.balanceOf(address(this));
        uint256 dynamicRewardsBalanceBefore = ELON.balanceOf(dynamicRewards);

        vm.expectEmit(true, true, true, false, address(miner));

        emit MinerETHv2.ClaimRewards(address(this), rewardsAccrued);

        uint256 rewards = miner.claimRewards();
        uint256 rewardsAccruedAfter = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        assertEq(0, rewardsAccruedAfter);
        assertEq(elonBalanceBefore + rewards, ELON.balanceOf(address(this)));
        assertLe(
            dynamicRewardsBalanceBefore - rewards,
            ELON.balanceOf(dynamicRewards)
        );
        assertLe(rewardsAccrued, rewards);
    }
}
