// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solady/tokens/ERC20.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import {IBrrETH} from "src/interfaces/IBrrETH.sol";
import {IBrrETHRedeemHelper} from "src/interfaces/IBrrETHRedeemHelper.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IRouter} from "src/interfaces/IRouter.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

contract MinerETH is ERC20, ReentrancyGuard {
    using SafeTransferLib for address;

    address private constant _SWAP_REFERRER = address(0);
    uint256 private constant _DEPOSIT_BUFFER = 10;
    IBrrETH private constant _BRR_ETH =
        IBrrETH(0xf1288441F094d0D73bcA4E57dDd07829B34de681);
    IBrrETHRedeemHelper private constant _BRR_ETH_HELPER =
        IBrrETHRedeemHelper(0x787417F293260E9800327ABFeE99874B108a6c5b);
    IRouter private constant _ROUTER =
        IRouter(0xe88483B5901FA3537355C4324ccF92a8d4155260);
    IWETH private constant _WETH =
        IWETH(0x4200000000000000000000000000000000000006);
    IRewardsDistributor private constant _REWARDS_DISTRIBUTOR =
        IRewardsDistributor(0x29E6fCeEd934E97D3C5dE1F75dAb604C29cE055e);
    address private constant _REWARDS_STORE =
        0xAc136DD22c5A2ea317AB69979e8363AdD51D6a51;
    string private _tokenName;
    string private _tokenSymbol;
    bytes32 private immutable _pair;

    /// @notice The reward token address.
    address public immutable rewardToken;

    event Deposit(address indexed msgSender, uint256 amount);
    event Withdraw(address indexed msgSender, uint256 amount);
    event Mine(address indexed msgSender, uint256 interest, uint256 rewards);
    event ClaimRewards(address indexed msgSender, uint256 rewards);

    error InvalidAddress();
    error InvalidAmount();
    error InvalidTokenName();
    error InvalidTokenSymbol();

    /**
     * @notice There should never be ETH sitting in this contract, but in the event that there
     *         is, it will be converted into rewards (via `mine`) and claimed by token holders.
     */
    receive() external payable {}

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        address _rewardToken
    ) {
        if (bytes(tokenName).length == 0) revert InvalidTokenName();
        if (bytes(tokenSymbol).length == 0) revert InvalidTokenSymbol();
        if (_rewardToken == address(0)) revert InvalidAddress();

        _tokenName = tokenName;
        _tokenSymbol = tokenSymbol;
        rewardToken = _rewardToken;
        _pair = keccak256(abi.encodePacked(address(_WETH), _rewardToken));

        address(_WETH).safeApprove(address(_ROUTER), type(uint256).max);
        address(_BRR_ETH).safeApprove(
            address(_BRR_ETH_HELPER),
            type(uint256).max
        );
    }

    /**
     * @notice Accrue user rewards upon transfers.
     * @param  from  address  Token sender.
     * @param  to    address  Token receiver.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal override {
        if (from == address(0)) {
            _REWARDS_DISTRIBUTOR.accrue(SolmateERC20(address(this)), to);
        } else if (to == address(0)) {
            _REWARDS_DISTRIBUTOR.accrue(SolmateERC20(address(this)), from);
        } else {
            _REWARDS_DISTRIBUTOR.accrue(SolmateERC20(address(this)), from, to);
        }
    }

    /// @notice Returns the name of the token.
    function name() public view override returns (string memory) {
        return _tokenName;
    }

    /// @notice Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }

    /// @notice Returns the decimals places of the token.
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function _mine() private returns (uint256 interest, uint256 rewards) {
        _BRR_ETH.harvest();

        uint256 _totalSupplyWithBuffer = totalSupply() + _DEPOSIT_BUFFER;
        uint256 sharesBalance = _BRR_ETH.balanceOf(address(this));

        if (sharesBalance == 0) return (0, 0);

        _BRR_ETH_HELPER.redeem(sharesBalance, address(this));
        _BRR_ETH.deposit{value: _totalSupplyWithBuffer}(address(this));

        interest = address(this).balance;

        if (interest != 0) {
            _WETH.deposit{value: interest}();

            (uint256 index, uint256 quote) = _ROUTER.getSwapOutput(
                _pair,
                interest
            );

            if (quote != 0) {
                rewards = _ROUTER.swap(
                    address(_WETH),
                    rewardToken,
                    interest,
                    quote,
                    index,
                    _SWAP_REFERRER
                );

                rewardToken.safeTransfer(address(_REWARDS_STORE), rewards);
                _REWARDS_DISTRIBUTOR.accrue(
                    SolmateERC20(address(this)),
                    msg.sender
                );
            }
        }

        emit Mine(msg.sender, interest, rewards);
    }

    /// @notice Mine rewards.
    function mine() external nonReentrant returns (uint256, uint256) {
        return _mine();
    }

    /// @notice Deposit assets.
    function deposit() external payable nonReentrant {
        if (msg.value == 0) revert InvalidAmount();

        _WETH.deposit{value: msg.value}();
        _mine();
        _WETH.withdraw(msg.value);
        _BRR_ETH.deposit{value: msg.value}(address(this));
        _mint(msg.sender, msg.value);

        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw assets.
     * @param  amount  uint256  Token amount.
     */
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();

        _mine();
        _burn(msg.sender, amount);

        uint256 sharesBalance = _BRR_ETH.balanceOf(address(this));

        _BRR_ETH_HELPER.redeem(sharesBalance, address(this));

        uint256 redepositAmount = address(this).balance - amount;

        if (redepositAmount != 0)
            _BRR_ETH.deposit{value: redepositAmount}(address(this));

        msg.sender.safeTransferETH(amount);

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice Claim rewards.
     * @return rewards  uint256  Rewards claimed.
     */
    function claimRewards() external nonReentrant returns (uint256 rewards) {
        _mine();

        rewards = _REWARDS_DISTRIBUTOR.rewardsAccrued(msg.sender);

        if (rewards != 0) _REWARDS_DISTRIBUTOR.claimRewards(msg.sender);

        emit ClaimRewards(msg.sender, rewards);
    }
}
