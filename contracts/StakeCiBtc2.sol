// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SingleAdminAccessControl } from "./SingleAdminAccessControl.sol";

import { IRBTC20 } from "./interfaces/IRBTC20.sol";
import { ICiBtc } from "./interfaces/ICiBtc.sol";
import { TransferHelper } from "./utils/TransferHelper.sol";

contract StakeCiBtc2 is ReentrancyGuard, SingleAdminAccessControl {
    using SafeERC20 for IERC20;

    bytes32 private constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
    bytes32 private constant CIBTC_STAKER_ROLE = keccak256("CIBTC_STAKER_ROLE");

    IERC20 public immutable collateral;
    IRBTC20 public immutable rBTC;
    address public immutable ciBTC;

    event Withdraw(address, address);
    event Withdrawal(address user, uint amount, uint time);
    event Deposit(address token, address user, uint amount, uint time);

    event UpdateCollateral(address token, uint time);

    event UpdateRBTC20(address pre, address indexed newRBTC20);

    error InvalidZeroAddress();
    error InvalidAmount();
    error CantBlacklistOwner();
    error OperationNotAllowed();

    modifier notZero(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    modifier notOwner(address target) {
        if (target == owner()) revert CantBlacklistOwner();
        _;
    }

    constructor(address owner_, address rbtc_, address ciBTC_, IERC20 collateral_) {
        if (rbtc_ == address(0) || ciBTC_ == address(0) || owner_ == address(0) || address(collateral_) == address(0)) {
            revert InvalidZeroAddress();
        }

        ciBTC = ciBTC_;
        collateral = IERC20(collateral_);
        rBTC = IRBTC20(rbtc_);

        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    function withdrawTokensSelf(address token, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Cannot be zero address");
        if (token == address(0)) {
            (bool success, ) = to.call{ value: address(this).balance }("");
            if (!success) {
                revert();
            }
        } else {
            uint256 bal = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(to, bal);
        }
        emit Withdraw(token, to);
    }

    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notOwner(target) {
        _grantRole(CIBTC_STAKER_ROLE, target);
    }

    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notOwner(target) {
        _revokeRole(CIBTC_STAKER_ROLE, target);
    }

    function deposit(uint256 amount) public nonReentrant notZero(amount) {
        if (hasRole(CIBTC_STAKER_ROLE, msg.sender)) {
            revert OperationNotAllowed();
        }
        collateral.safeTransferFrom(msg.sender, address(this), amount);

        TransferHelper.safeApprove(address(collateral), address(rBTC), amount);
        uint beforeRBTC = rBTC.balanceOf(address(this));
        rBTC.deposit(amount);
        uint afterRBTC = rBTC.balanceOf(address(this));

        uint shareAmount = afterRBTC - beforeRBTC;
        ICiBtc(ciBTC).mintTo(msg.sender, shareAmount);

        emit Deposit(address(collateral), msg.sender, amount, block.timestamp);
    }

    function withdraw(uint256 amount) public nonReentrant notZero(amount) {
        if (hasRole(CIBTC_STAKER_ROLE, msg.sender)) {
            revert OperationNotAllowed();
        }
        require(amount <= IERC20(ciBTC).balanceOf(msg.sender), "INSUFFICIENT_ciBTC_BALANCE");

        uint beforeCollateral = collateral.balanceOf(address(this));
        rBTC.withdraw(amount);
        uint afterCollateral = collateral.balanceOf(address(this));

        IERC20(ciBTC).safeTransferFrom(msg.sender, address(this), amount);
        uint _balance = IERC20(ciBTC).balanceOf(address(this));
        ICiBtc(ciBTC).burn(_balance);

        collateral.safeTransfer(msg.sender, afterCollateral - beforeCollateral);

        emit Withdrawal(msg.sender, amount, block.timestamp);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    event Received(address, uint256);
}
