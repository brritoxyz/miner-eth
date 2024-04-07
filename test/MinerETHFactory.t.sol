// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {MinerETH} from "src/MinerETH.sol";
import {MinerETHFactory} from "src/MinerETHFactory.sol";

contract MinerETHFactoryTest is Test {
    address public constant ELON = 0xAa6Cccdce193698D33deb9ffd4be74eAa74c4898;
    string public constant TOKEN_NAME_PREFIX = "Brrito Miner-ETH/";
    string public constant TOKEN_SYMBOL_PREFIX = "brrMINER-ETH/";
    address public constant BRR_ETH =
        0xf1288441F094d0D73bcA4E57dDd07829B34de681;
    address public constant BRR_ETH_HELPER =
        0x787417F293260E9800327ABFeE99874B108a6c5b;
    address public constant ROUTER = 0xe88483B5901FA3537355C4324ccF92a8d4155260;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    uint256 public constant DEAD_SHARES_VALUE = 0.01 ether;
    MinerETHFactory public immutable factory = new MinerETHFactory();

    /*//////////////////////////////////////////////////////////////
                            deploy
    //////////////////////////////////////////////////////////////*/

    function testCannotDeployInvalidRewardToken() external {
        address rewardToken = address(0);

        vm.expectRevert(MinerETHFactory.InvalidRewardToken.selector);

        factory.deploy(rewardToken);
    }

    function testDeploy() external {
        address rewardToken = ELON;

        assertEq(address(0), factory.deployments(rewardToken));

        vm.expectEmit(true, true, true, true, address(factory));

        emit MinerETHFactory.Deploy(rewardToken);

        address clone = factory.deploy(rewardToken);

        assertTrue(clone != address(0));
        assertEq(clone, factory.deployments(rewardToken));

        MinerETH miner = MinerETH(payable(clone));

        vm.expectRevert(Initializable.InvalidInitialization.selector);

        miner.initialize(address(1), address(1), address(1));

        assertEq(type(uint256).max, ERC20(WETH).allowance(clone, ROUTER));
        assertEq(
            type(uint256).max,
            ERC20(BRR_ETH).allowance(clone, BRR_ETH_HELPER)
        );
    }
}
