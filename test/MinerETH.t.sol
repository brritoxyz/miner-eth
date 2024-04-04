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

contract MinerETHFactory {
    address public immutable implementation = address(new MinerETH());

    function deploy(
        address rewardToken,
        address rewardsDistributor,
        address rewardsStore
    ) external returns (address clone) {
        clone = LibClone.clone(implementation);

        MinerETH(payable(clone)).initialize(
            rewardToken,
            rewardsDistributor,
            rewardsStore
        );
    }
}

contract MinerETH_ElonRWATest is Test {
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
    IRewardsDistributor public immutable REWARDS_DISTRIBUTOR =
        IRewardsDistributor(0x29E6fCeEd934E97D3C5dE1F75dAb604C29cE055e);
    address public constant DYNAMIC_REWARDS =
        0x0cD65d30679931BEd0CfdA9C8bb4B43BE2e0ebd9;
    address public constant REWARDS_STORE =
        0xAc136DD22c5A2ea317AB69979e8363AdD51D6a51;
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
        miner = MinerETH(
            payable(
                factory.deploy(
                    ELON,
                    address(REWARDS_DISTRIBUTOR),
                    REWARDS_STORE
                )
            )
        );

        vm.prank(REWARDS_DISTRIBUTOR.owner());

        REWARDS_DISTRIBUTOR.addStrategyForRewards(SolmateERC20(address(miner)));

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
        (uint256 strategyIndex, ) = REWARDS_DISTRIBUTOR.strategyState(
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
        uint256 userIndex = REWARDS_DISTRIBUTOR.userIndex(
            SolmateERC20(address(miner)),
            address(this)
        );
        uint256 deltaIndex = estimatedStrategyIndex - userIndex;
        uint256 userTokens = miner.balanceOf(address(this));
        uint256 userDelta = (userTokens * deltaIndex) / 1e18;
        estimatedRewardsAccrued =
            REWARDS_DISTRIBUTOR.rewardsAccrued(address(this)) +
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
                            initialize
    //////////////////////////////////////////////////////////////*/

    function testCannotInitializeRewardTokenInvalidAddress() external {
        address rewardToken = address(0);
        address rewardsDistributor = address(REWARDS_DISTRIBUTOR);
        address rewardsStore = REWARDS_STORE;

        vm.expectRevert(MinerETH.InvalidAddress.selector);

        factory.deploy(rewardToken, rewardsDistributor, rewardsStore);
    }

    function testCannotInitializeRewardsDistributorInvalidAddress() external {
        address rewardToken = ELON;
        address rewardsDistributor = address(0);
        address rewardsStore = REWARDS_STORE;

        vm.expectRevert(MinerETH.InvalidAddress.selector);

        factory.deploy(rewardToken, rewardsDistributor, rewardsStore);
    }

    function testCannotInitializeRewardsStoreInvalidAddress() external {
        address rewardToken = ELON;
        address rewardsDistributor = address(REWARDS_DISTRIBUTOR);
        address rewardsStore = address(0);

        vm.expectRevert(MinerETH.InvalidAddress.selector);

        factory.deploy(rewardToken, rewardsDistributor, rewardsStore);
    }

    function testCannotInitializeInvalidInitialization() external {
        address rewardToken = ELON;
        address rewardsDistributor = address(REWARDS_DISTRIBUTOR);
        address rewardsStore = REWARDS_STORE;
        MinerETH testMiner = MinerETH(
            payable(
                factory.deploy(rewardToken, rewardsDistributor, rewardsStore)
            )
        );

        vm.expectRevert(Initializable.InvalidInitialization.selector);

        testMiner.initialize(rewardToken, rewardsDistributor, rewardsStore);
    }

    function testInitialize() external {
        address rewardToken = ELON;
        address rewardsDistributor = address(REWARDS_DISTRIBUTOR);
        address rewardsStore = REWARDS_STORE;
        MinerETH testMiner = MinerETH(
            payable(
                factory.deploy(rewardToken, rewardsDistributor, rewardsStore)
            )
        );

        assertEq(rewardToken, testMiner.rewardToken());
        assertEq(rewardsDistributor, address(testMiner.rewardsDistributor()));
        assertEq(rewardsStore, testMiner.rewardsStore());
        assertEq(
            type(uint256).max,
            ERC20(address(WETH)).allowance(address(testMiner), address(ROUTER))
        );
        assertEq(
            type(uint256).max,
            ERC20(address(BRR_ETH)).allowance(
                address(testMiner),
                address(BRR_ETH_HELPER)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                            mine
    //////////////////////////////////////////////////////////////*/

    function testMine() external {
        miner.deposit{value: 1e18}("");

        skip(1 days);

        BRR_ETH.harvest();

        uint256 minerTotalSupply = miner.totalSupply();
        uint256 dynamicRewardsElonBalance = ELON.balanceOf(DYNAMIC_REWARDS);
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
        ) = REWARDS_DISTRIBUTOR.strategyState(SolmateERC20(address(miner)));
        uint256 rewardsAccrued = REWARDS_DISTRIBUTOR.rewardsAccrued(
            address(this)
        );

        // Invariant.
        assertEq(minerTotalSupply, miner.totalSupply());
        assertEq(
            dynamicRewardsElonBalance + rewards,
            ELON.balanceOf(DYNAMIC_REWARDS)
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
        uint256 dynamicRewardsElonBalance = ELON.balanceOf(DYNAMIC_REWARDS);
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
        ) = REWARDS_DISTRIBUTOR.strategyState(SolmateERC20(address(miner)));
        uint256 rewardsAccrued = REWARDS_DISTRIBUTOR.rewardsAccrued(
            address(this)
        );

        assertEq(minerTotalSupply, miner.totalSupply());
        assertEq(
            dynamicRewardsElonBalance + rewards,
            ELON.balanceOf(DYNAMIC_REWARDS)
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

        uint256 rewardsAccrued = REWARDS_DISTRIBUTOR.rewardsAccrued(
            address(this)
        );
        uint256 elonBalanceBefore = ELON.balanceOf(address(this));
        uint256 dynamicRewardsElonBalanceBefore = ELON.balanceOf(
            DYNAMIC_REWARDS
        );

        vm.expectEmit(true, true, true, false, address(miner));

        emit ClaimRewards(address(this), rewardsAccrued);

        uint256 rewards = miner.claimRewards();
        uint256 rewardsAccruedAfter = REWARDS_DISTRIBUTOR.rewardsAccrued(
            address(this)
        );

        assertEq(0, rewardsAccruedAfter);
        assertEq(elonBalanceBefore + rewards, ELON.balanceOf(address(this)));
        assertLe(
            dynamicRewardsElonBalanceBefore - rewards,
            ELON.balanceOf(DYNAMIC_REWARDS)
        );
        assertLe(rewardsAccrued, rewards);
    }

    function testClaimRewardsFuzz(uint256 amount) external {
        amount = bound(amount, 1e6, 100e18);

        miner.deposit{value: amount}("");

        skip(5);

        uint256 rewardsAccrued = REWARDS_DISTRIBUTOR.rewardsAccrued(
            address(this)
        );
        uint256 elonBalanceBefore = ELON.balanceOf(address(this));
        uint256 dynamicRewardsElonBalanceBefore = ELON.balanceOf(
            DYNAMIC_REWARDS
        );

        vm.expectEmit(true, true, true, false, address(miner));

        emit ClaimRewards(address(this), rewardsAccrued);

        uint256 rewards = miner.claimRewards();
        uint256 rewardsAccruedAfter = REWARDS_DISTRIBUTOR.rewardsAccrued(
            address(this)
        );

        assertEq(0, rewardsAccruedAfter);
        assertEq(elonBalanceBefore + rewards, ELON.balanceOf(address(this)));
        assertLe(
            dynamicRewardsElonBalanceBefore - rewards,
            ELON.balanceOf(DYNAMIC_REWARDS)
        );
        assertLe(rewardsAccrued, rewards);
    }
}
