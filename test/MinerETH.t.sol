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
import {IBrrETH} from "test/interfaces/IBrrETH.sol";
import {MinerETH} from "src/MinerETH.sol";
import {MinerETHFactory} from "src/MinerETHFactory.sol";

contract MinerETHTest is Test {
    using LibString for string;
    using SafeTransferLib for address;

    IBrrETH public constant BRR_ETH =
        IBrrETH(0xf1288441F094d0D73bcA4E57dDd07829B34de681);
    address public constant BRR_ETH_HELPER =
        0x787417F293260E9800327ABFeE99874B108a6c5b;
    IWETH public constant WETH =
        IWETH(0x4200000000000000000000000000000000000006);
    address public constant ELON = 0xAa6Cccdce193698D33deb9ffd4be74eAa74c4898;
    IRouter public constant ROUTER =
        IRouter(0xe88483B5901FA3537355C4324ccF92a8d4155260);
    uint256 public constant COMET_SLIPPAGE = 10;
    string public constant TOKEN_NAME = "Brrito Miner-ETH/ElonRWA";
    string public constant TOKEN_SYMBOL = "brrMINER-ETH/ElonRWA";
    uint256 public constant TOKEN_DECIMALS = 18;
    uint256 public constant DEAD_SHARES_VALUE = 0.01 ether;
    MinerETHFactory public immutable factory = new MinerETHFactory();
    MinerETH public immutable miner;
    IRewardsDistributor public immutable rewardsDistributor;
    address public immutable dynamicRewards;
    address public immutable rewardsStore;

    receive() external payable {}

    constructor() {
        miner = MinerETH(payable(factory.deploy(ELON)));
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
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));
        (uint256 strategyIndex, ) = rewardsDistributor.strategyState(
            SolmateERC20(address(miner))
        );
        uint256 redeemedAssets = BRR_ETH.convertToAssets(minerSharesBalance) -
            COMET_SLIPPAGE;
        uint256 redepositedAssets = (
            redeemedAssets > minerTotalSupply
                ? minerTotalSupply
                : redeemedAssets
        ) - COMET_SLIPPAGE;
        estimatedRedepositShares = BRR_ETH.convertToShares(redepositedAssets);
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
        MinerETH newMiner = MinerETH(payable(factory.deploy(address(WETH))));

        assertEq(0, newMiner.totalSupply());

        (uint256 interest, uint256 rewards) = newMiner.mine();

        assertEq(0, interest);
        assertEq(0, rewards);
    }

    function testMineWithCometDeficit() external {
        miner.mine();

        uint256 sharesBefore = BRR_ETH.balanceOf(address(miner));
        uint256 assetsBefore = BRR_ETH.convertToAssets(sharesBefore);

        // Calling mine multiple times in the same block will lead to less shares, less assets.
        // As of this writing, 500 iterations exceeds the 60M block gas limit.
        for (uint256 i = 0; i < 500; ++i) {
            miner.mine();
        }

        uint256 sharesAfter = BRR_ETH.balanceOf(address(miner));
        uint256 assetsAfter = BRR_ETH.convertToAssets(sharesAfter);

        assertLe(sharesAfter, sharesBefore);
        assertLe(assetsAfter, assetsBefore);

        skip(1);

        uint256 assetsAfterInterestAccrual = BRR_ETH.convertToAssets(
            BRR_ETH.balanceOf(address(miner))
        );

        // The interest accrued from the initial deposit, in a single block, will exceed the rounding losses
        // resulting from 500 iterations of calling `mine`.
        assertLe(assetsBefore, assetsAfterInterestAccrual);
        assertLe(miner.totalSupply(), assetsAfterInterestAccrual);
    }

    function testMine() external {
        // Forward a block to accrue interest.
        vm.roll(block.number + 1);

        // Harvesting before calling `mine` makes it easier for us to calculate expected values.
        BRR_ETH.harvest();

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
        assertLe(estimatedRedepositShares, BRR_ETH.balanceOf(address(miner)));
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
        BRR_ETH.harvest();

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
        assertLe(estimatedRedepositShares, BRR_ETH.balanceOf(address(miner)));
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

        vm.expectRevert(MinerETH.InvalidAmount.selector);

        miner.deposit{value: amount}(memo);
    }

    function testDeposit() external {
        BRR_ETH.harvest();

        uint256 amount = 1 ether;
        string memory memo = "test";
        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupplyBefore = miner.totalSupply();
        (
            uint256 estimatedRedepositShares,
            ,
            uint256 estimatedRewards,
            uint256 estimatedStrategyIndex,
            uint256 estimatedRewardsAccrued
        ) = _getEstimates();
        uint256 newShares = BRR_ETH.convertToShares(amount - COMET_SLIPPAGE);
        uint256 dynamicRewardsBalance = ELON.balanceOf(dynamicRewards);

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETH.Deposit(address(this), memo.packOne(), amount);

        miner.deposit{value: amount}(memo);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter - COMET_SLIPPAGE;
        (uint256 strategyIndex, ) = rewardsDistributor.strategyState(
            SolmateERC20(address(miner))
        );
        uint256 rewardsAccrued = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        // Invariant.
        assertEq(tokenBalanceBefore + amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupplyBefore + amount, minerTotalSupplyAfter);
        assertLt(0, minerTotalSupplyAfter);
        assertLt(0, minerSharesBalance);
        assertLt(0, principalWithSlippage);
        assertLt(0, estimatedRedepositShares);
        assertLt(0, estimatedRewards);
        assertLt(0, estimatedStrategyIndex);
        assertLt(0, estimatedRewardsAccrued);

        // Estimates.
        assertLe(
            principalWithSlippage,
            BRR_ETH.convertToAssets(minerSharesBalance)
        );
        assertLe(estimatedRedepositShares + newShares, minerSharesBalance);
        assertLe(
            estimatedRewards + dynamicRewardsBalance,
            ELON.balanceOf(dynamicRewards)
        );
        assertLe(estimatedStrategyIndex, strategyIndex);
        assertLe(estimatedRewardsAccrued, rewardsAccrued);
    }

    function testDepositFuzz(uint256 amount, string calldata memo) external {
        amount = bound(amount, 1e2, 1_000 ether);

        deal(address(this), amount);

        BRR_ETH.harvest();

        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupplyBefore = miner.totalSupply();
        (
            uint256 estimatedRedepositShares,
            ,
            uint256 estimatedRewards,
            ,

        ) = _getEstimates();
        uint256 newShares = BRR_ETH.convertToShares(amount - COMET_SLIPPAGE);
        uint256 dynamicRewardsBalance = ELON.balanceOf(dynamicRewards);

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETH.Deposit(address(this), memo.packOne(), amount);

        miner.deposit{value: amount}(memo);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter - COMET_SLIPPAGE;

        // Invariant.
        assertEq(tokenBalanceBefore + amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupplyBefore + amount, minerTotalSupplyAfter);
        assertLt(0, minerTotalSupplyAfter);
        assertLt(0, minerSharesBalance);
        assertLt(0, principalWithSlippage);
        assertLt(0, estimatedRedepositShares);
        assertLt(0, estimatedRewards);

        // Estimates.
        assertLe(
            principalWithSlippage,
            BRR_ETH.convertToAssets(minerSharesBalance)
        );
        assertLe(estimatedRedepositShares + newShares, minerSharesBalance);
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

        vm.expectRevert(MinerETH.InvalidAmount.selector);

        miner.withdraw(amount);
    }

    function testWithdraw() external {
        uint256 amount = 1 ether;

        miner.deposit{value: amount}("");

        skip(1);

        BRR_ETH.harvest();

        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();
        (
            uint256 estimatedRedepositShares,
            ,
            uint256 estimatedRewards,
            ,

        ) = _getEstimates();
        uint256 removedShares = BRR_ETH.convertToShares(
            amount + COMET_SLIPPAGE
        );
        uint256 rewardsAccruedBefore = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETH.Withdraw(address(this), amount);

        miner.withdraw(amount);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter - COMET_SLIPPAGE;
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
            BRR_ETH.convertToAssets(minerSharesBalance)
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

        BRR_ETH.harvest();

        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();
        (
            uint256 estimatedRedepositShares,
            ,
            uint256 estimatedRewards,
            ,

        ) = _getEstimates();
        uint256 removedShares = BRR_ETH.convertToShares(
            amount + COMET_SLIPPAGE
        );
        uint256 rewardsAccruedBefore = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETH.Withdraw(address(this), amount);

        miner.withdraw(amount);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter - COMET_SLIPPAGE;
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
            BRR_ETH.convertToAssets(minerSharesBalance)
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

        BRR_ETH.harvest();

        uint256 withdrawalAmount = amount / withdrawalDivisor;
        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();
        (
            uint256 estimatedRedepositShares,
            ,
            uint256 estimatedRewards,
            ,

        ) = _getEstimates();
        uint256 removedShares = BRR_ETH.convertToShares(
            amount + COMET_SLIPPAGE
        );
        uint256 rewardsAccruedBefore = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        vm.expectEmit(true, true, true, true, address(miner));

        emit MinerETH.Withdraw(address(this), withdrawalAmount);

        miner.withdraw(withdrawalAmount);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));
        uint256 principalWithSlippage = minerTotalSupplyAfter - COMET_SLIPPAGE;
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
            BRR_ETH.convertToAssets(minerSharesBalance)
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

        emit MinerETH.ClaimRewards(address(this), rewardsAccrued);

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

        emit MinerETH.ClaimRewards(address(this), rewardsAccrued);

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
