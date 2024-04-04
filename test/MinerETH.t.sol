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
    IRewardsDistributor public immutable rewardsDistributor;
    address public immutable dynamicRewards;
    address public immutable rewardsStore;
    MinerETHFactory public immutable factory = new MinerETHFactory();
    MinerETH public immutable miner;

    event Deposit(
        address indexed msgSender,
        bytes32 indexed memo,
        uint256 amount
    );
    event Withdraw(address indexed msgSender, uint256 amount);
    event Mine(address indexed msgSender, uint256 interest, uint256 rewards);
    event ClaimRewards(address indexed msgSender, uint256 rewards);

    error InsufficientSharesMinted();

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

        deal(address(this), 1000e18);

        address(0xbeef).safeTransferETH(1e18);

        vm.prank(address(0xbeef));

        miner.deposit{value: 1e18}("");

        skip(1 days);
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
        uint256 redeposit = minerTotalSupply + COMET_SLIPPAGE;
        (uint256 strategyIndex, ) = rewardsDistributor.strategyState(
            SolmateERC20(address(miner))
        );
        uint256 redeemedAssets = BRR_ETH.convertToAssets(minerSharesBalance) -
            COMET_SLIPPAGE;
        estimatedRedepositShares = BRR_ETH.convertToShares(
            redeposit - COMET_SLIPPAGE
        );
        estimatedInterest = redeemedAssets - redeposit;
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

    function testMine() external {
        miner.deposit{value: 1e18}("");

        skip(1 days);

        BRR_ETH.harvest();

        uint256 minerTotalSupply = miner.totalSupply();
        uint256 dynamicRewardsElonBalance = ELON.balanceOf(dynamicRewards);
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
            dynamicRewardsElonBalance + rewards,
            ELON.balanceOf(dynamicRewards)
        );
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertEq(0, address(WETH).balanceOf(address(miner)));
        assertEq(0, ELON.balanceOf(address(miner)));

        // Estimates.
        assertLe(estimatedRedepositShares, BRR_ETH.balanceOf(address(miner)));
        assertLe(estimatedInterest, interest);
        assertLe(estimatedRewards, rewards);
        assertLe(estimatedStrategyIndex, strategyIndex);
        assertLe(estimatedRewardsAccrued, rewardsAccrued);
    }

    function testMineFuzz(uint256 skipTime) external {
        skipTime = bound(skipTime, 1, 365 days);

        skip(skipTime);

        BRR_ETH.harvest();

        uint256 minerTotalSupply = miner.totalSupply();
        uint256 dynamicRewardsElonBalance = ELON.balanceOf(dynamicRewards);
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

        assertEq(minerTotalSupply, miner.totalSupply());
        assertEq(
            dynamicRewardsElonBalance + rewards,
            ELON.balanceOf(dynamicRewards)
        );
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertEq(0, address(WETH).balanceOf(address(miner)));
        assertEq(0, ELON.balanceOf(address(miner)));
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
        uint256 amount = 1e18;
        string memory memo = "test";
        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();

        vm.expectEmit(true, true, true, true, address(miner));

        emit Deposit(address(this), memo.packOne(), amount);

        miner.deposit{value: amount}(memo);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));

        // Invariant.
        assertEq(tokenBalanceBefore + amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupply + amount, minerTotalSupplyAfter);

        // Estimates.
        assertLe(
            minerTotalSupplyAfter,
            BRR_ETH.convertToAssets(minerSharesBalance)
        );
    }

    function testDepositFuzz(uint256 amount, string calldata memo) external {
        amount = bound(amount, 1e6, 100e18);
        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();

        vm.expectEmit(true, true, true, true, address(miner));

        emit Deposit(address(this), memo.packOne(), amount);

        miner.deposit{value: amount}(memo);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));

        // Invariant.
        assertEq(tokenBalanceBefore + amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupply + amount, minerTotalSupplyAfter);

        // Estimates.
        assertLe(
            minerTotalSupplyAfter,
            BRR_ETH.convertToAssets(minerSharesBalance)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            withdraw
    //////////////////////////////////////////////////////////////*/

    function testCannotWithrawInvalidAmount() external {
        uint256 amount = 0;

        vm.expectRevert(MinerETH.InvalidAmount.selector);

        miner.withdraw(amount);
    }

    function testWithdraw() external {
        uint256 amount = 1e18;

        miner.deposit{value: amount}("");
        skip(60);

        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();

        vm.expectEmit(true, true, true, true, address(miner));

        emit Withdraw(address(this), amount);

        miner.withdraw(amount);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));

        // Invariant.
        assertEq(tokenBalanceBefore - amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupply - amount, minerTotalSupplyAfter);

        // Estimates.
        assertLe(
            minerTotalSupplyAfter,
            BRR_ETH.convertToAssets(minerSharesBalance)
        );
    }

    function testWithdrawFuzz(uint256 amount) external {
        amount = bound(amount, 1e6, 100e18);

        miner.deposit{value: amount}("");
        skip(60);

        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();

        vm.expectEmit(true, true, true, true, address(miner));

        emit Withdraw(address(this), amount);

        miner.withdraw(amount);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));

        // Invariant.
        assertEq(tokenBalanceBefore - amount, miner.balanceOf(address(this)));
        assertEq(minerTotalSupply - amount, minerTotalSupplyAfter);

        // Estimates.
        assertLe(
            minerTotalSupplyAfter,
            BRR_ETH.convertToAssets(minerSharesBalance)
        );
    }

    function testWithdrawPartialFuzz(
        uint256 amount,
        uint256 withdrawalDivisor
    ) external {
        amount = bound(amount, 1e6, 100e18);
        withdrawalDivisor = bound(withdrawalDivisor, 1, type(uint8).max);

        miner.deposit{value: amount}("");
        skip(60);

        uint256 withdrawalAmount = amount / withdrawalDivisor;
        uint256 tokenBalanceBefore = miner.balanceOf(address(this));
        uint256 minerTotalSupply = miner.totalSupply();

        vm.expectEmit(true, true, true, true, address(miner));

        emit Withdraw(address(this), withdrawalAmount);

        miner.withdraw(withdrawalAmount);

        uint256 minerTotalSupplyAfter = miner.totalSupply();
        uint256 minerSharesBalance = BRR_ETH.balanceOf(address(miner));

        // Invariant.
        assertEq(
            tokenBalanceBefore - withdrawalAmount,
            miner.balanceOf(address(this))
        );
        assertEq(minerTotalSupply - withdrawalAmount, minerTotalSupplyAfter);

        // Estimates.
        assertLe(
            minerTotalSupplyAfter,
            BRR_ETH.convertToAssets(minerSharesBalance)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            claimRewards
    //////////////////////////////////////////////////////////////*/

    function testClaimRewards() external {
        uint256 amount = 1e18;

        miner.deposit{value: amount}("");

        skip(5);

        uint256 rewardsAccrued = rewardsDistributor.rewardsAccrued(
            address(this)
        );
        uint256 elonBalanceBefore = ELON.balanceOf(address(this));
        uint256 dynamicRewardsElonBalanceBefore = ELON.balanceOf(
            dynamicRewards
        );

        vm.expectEmit(true, true, true, false, address(miner));

        emit ClaimRewards(address(this), rewardsAccrued);

        uint256 rewards = miner.claimRewards();
        uint256 rewardsAccruedAfter = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        assertEq(0, rewardsAccruedAfter);
        assertEq(elonBalanceBefore + rewards, ELON.balanceOf(address(this)));
        assertLe(
            dynamicRewardsElonBalanceBefore - rewards,
            ELON.balanceOf(dynamicRewards)
        );
        assertLe(rewardsAccrued, rewards);
    }

    function testClaimRewardsFuzz(uint256 amount) external {
        amount = bound(amount, 1e6, 100e18);

        miner.deposit{value: amount}("");

        skip(5);

        uint256 rewardsAccrued = rewardsDistributor.rewardsAccrued(
            address(this)
        );
        uint256 elonBalanceBefore = ELON.balanceOf(address(this));
        uint256 dynamicRewardsElonBalanceBefore = ELON.balanceOf(
            dynamicRewards
        );

        vm.expectEmit(true, true, true, false, address(miner));

        emit ClaimRewards(address(this), rewardsAccrued);

        uint256 rewards = miner.claimRewards();
        uint256 rewardsAccruedAfter = rewardsDistributor.rewardsAccrued(
            address(this)
        );

        assertEq(0, rewardsAccruedAfter);
        assertEq(elonBalanceBefore + rewards, ELON.balanceOf(address(this)));
        assertLe(
            dynamicRewardsElonBalanceBefore - rewards,
            ELON.balanceOf(dynamicRewards)
        );
        assertLe(rewardsAccrued, rewards);
    }
}
