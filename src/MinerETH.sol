// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solady/tokens/ERC20.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import {IBrrETH} from "src/interfaces/IBrrETH.sol";
import {IBrrETHRedeemHelper} from "src/interfaces/IBrrETHRedeemHelper.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IRouter} from "src/interfaces/IRouter.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

/**
 * @title Brrito token mining vaults.
 * @notice Deposit ETH and earn token rewards. Withdraw 100% of your principal at any time.
 * @author Brrito.xyz (kp | kphed.eth)
 */
contract MinerETH is ERC20, Initializable, ReentrancyGuard {
    using LibString for string;
    using SafeTransferLib for address;

    address private constant _SWAP_REFERRER = address(0);
    string private constant _TOKEN_NAME_PREFIX = "Brrito Miner-ETH/";
    string private constant _TOKEN_SYMBOL_PREFIX = "brrMINER-ETH/";
    IBrrETH private constant _BRR_ETH =
        IBrrETH(0xf1288441F094d0D73bcA4E57dDd07829B34de681);
    IBrrETHRedeemHelper private constant _BRR_ETH_HELPER =
        IBrrETHRedeemHelper(0x787417F293260E9800327ABFeE99874B108a6c5b);
    IRouter private constant _ROUTER =
        IRouter(0xe88483B5901FA3537355C4324ccF92a8d4155260);
    IWETH private constant _WETH =
        IWETH(0x4200000000000000000000000000000000000006);
    string private _name;
    string private _symbol;
    bytes32 private _pair;

    /// @notice Reward token.
    address public rewardToken;

    /// @notice Reward distributor contract.
    IRewardsDistributor public rewardsDistributor;

    /// @notice Reward storage contract.
    address public rewardsStore;

    event Deposit(
        address indexed msgSender,
        bytes32 indexed memo,
        uint256 amount
    );
    event Withdraw(address indexed msgSender, uint256 amount);
    event Mine(address indexed msgSender, uint256 interest, uint256 rewards);
    event ClaimRewards(address indexed msgSender, uint256 rewards);

    error InvalidAddress();
    error InvalidAmount();

    /**
     * @notice There should never be ETH sitting in this contract, but in the event that there
     *         is, it will be converted into rewards (via `mine`) and claimed by token holders.
     */
    receive() external payable {}

    constructor() {
        // Prevent implementation from being initialized.
        _disableInitializers();
    }

    function initialize(
        address _rewardToken,
        address _rewardsDistributor,
        address _rewardsStore
    ) external initializer {
        if (_rewardToken == address(0)) revert InvalidAddress();
        if (_rewardsDistributor == address(0)) revert InvalidAddress();
        if (_rewardsStore == address(0)) revert InvalidAddress();

        _name = string.concat(_TOKEN_NAME_PREFIX, ERC20(_rewardToken).name());
        _symbol = string.concat(
            _TOKEN_SYMBOL_PREFIX,
            ERC20(_rewardToken).symbol()
        );
        _pair = keccak256(abi.encodePacked(address(_WETH), _rewardToken));
        rewardToken = _rewardToken;
        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
        rewardsStore = _rewardsStore;

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
            rewardsDistributor.accrue(SolmateERC20(address(this)), to);
        } else if (to == address(0)) {
            rewardsDistributor.accrue(SolmateERC20(address(this)), from);
        } else {
            rewardsDistributor.accrue(SolmateERC20(address(this)), from, to);
        }
    }

    /// @notice Returns the name of the token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the decimals places of the token.
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Mine rewards.
     * @return interest  uint256  Interest generated.
     * @return rewards   uint256  Rewards mined.
     */
    function _mine() private returns (uint256 interest, uint256 rewards) {
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) return (0, 0);

        _BRR_ETH.harvest();
        _BRR_ETH_HELPER.redeem(
            _BRR_ETH.balanceOf(address(this)),
            address(this)
        );

        // Comet rounding may lead to the redeemed ETH being less than the total supply,
        // but the interest accrued per block should more than make up for it.
        if (address(this).balance < _totalSupply) {
            _BRR_ETH.deposit{value: address(this).balance}(address(this));
        } else {
            _BRR_ETH.deposit{value: _totalSupply}(address(this));

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

                    rewardToken.safeTransfer(rewardsStore, rewards);
                    rewardsDistributor.accrue(
                        SolmateERC20(address(this)),
                        msg.sender
                    );
                } else {
                    // Unwrap ETH, which will roll over to the next `mine`.
                    _WETH.withdraw(interest);
                }
            }
        }

        emit Mine(msg.sender, interest, rewards);
    }

    /// @notice Mine rewards.
    function mine() external nonReentrant returns (uint256, uint256) {
        return _mine();
    }

    /**
     * @notice Deposit assets.
     * @param  memo  string  Arbitrary data for offchain tracking purposes.
     */
    function deposit(string calldata memo) external payable nonReentrant {
        if (msg.value == 0) revert InvalidAmount();

        _WETH.deposit{value: msg.value}();
        _mine();
        _WETH.withdraw(msg.value);
        _BRR_ETH.deposit{value: msg.value}(address(this));
        _mint(msg.sender, msg.value);

        emit Deposit(msg.sender, memo.packOne(), msg.value);
    }

    /**
     * @notice Withdraw assets.
     * @param  amount  uint256  Token amount.
     */
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();

        _mine();
        _burn(msg.sender, amount);
        _BRR_ETH_HELPER.redeem(
            _BRR_ETH.balanceOf(address(this)),
            address(this)
        );

        uint256 redepositAmount = address(this).balance - amount;

        if (redepositAmount != 0)
            _BRR_ETH.deposit{value: redepositAmount}(address(this));

        msg.sender.forceSafeTransferETH(amount);

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice Claim rewards.
     * @return rewards  uint256  Rewards claimed.
     */
    function claimRewards() external nonReentrant returns (uint256 rewards) {
        _mine();

        rewards = rewardsDistributor.rewardsAccrued(msg.sender);

        if (rewards != 0) rewardsDistributor.claimRewards(msg.sender);

        emit ClaimRewards(msg.sender, rewards);
    }
}
