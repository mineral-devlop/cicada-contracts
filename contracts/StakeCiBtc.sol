// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SingleAdminAccessControl } from "./SingleAdminAccessControl.sol";
import { IRBTC } from "./interfaces/IRBTC.sol";
import { IRBTC20 } from "./interfaces/IRBTC20.sol";
import { ICiBtc } from "./interfaces/ICiBtc.sol";
import { TransferHelper } from "./utils/TransferHelper.sol";

contract StakeCiBtc is ReentrancyGuard, SingleAdminAccessControl {
    using SafeERC20 for IERC20;

    bytes32 private constant OP_ROLE = keccak256("OP_ROLE");

    bytes32 private constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
    bytes32 private constant CIBTC_STAKER_ROLE = keccak256("CIBTC_STAKER_ROLE");

    // keccak256("withdraw(uint256 chainId,address token, uint256 id,,uint256 assets,uint256 amount,address user,uint deadline)")
    bytes32 private constant WITHDRAW_TYPEHASH = 0x05028e3df2119a29fc6e3fab36fba05f56a3617958d96cf959a7487397e09e97;

    // keccak256("deposit(uint256 chainId,address token,uint256 id,uint256 amount,uint256 shares,address user,uint deadline)")
    bytes32 private constant DEPOSIT_TYPEHASH = 0x849e29044a1376626f7ff98481a4351bcc6bed2a187b60272e62a9d01bbf9599;

    IRBTC public _rBtc;
    IRBTC20 public _rBtc20;

    mapping(uint256 => bool) public withdraws;
    mapping(uint256 => bool) public deposits;

    address signer = 0x3862A837c0Fd3b9eEE18C8945335c98a4F27Fb87;

    address public immutable ciBTC;

    mapping(address => bool) public supportTokens;
    event Withdraw(address, address);
    event Withdrawal(uint id, address user, uint amount, uint time);
    event Deposit(address token, address user, uint amount, uint shares, uint time);
    event UpdateManager(address preManager, address indexed newManager);
    event UpdateSupportToken(address token, bool support);
    event UpdateRBTC(address pre, address indexed newRBTC);
    event UpdateRBTC20(address pre, address indexed newRBTC20);
    event DepositRBTC(address token, address user, uint amount, uint time);
    event WithdrawRBTC(address token, address user, uint amount, uint time);
    error InvalidZeroAddress();
    error InvalidAmount();
    error CantBlacklistOwner();
    error OperationNotAllowed();
    error InvalidToken();

    modifier notZero(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    modifier notSupportToken(address token) {
        if (supportTokens[token] != true) revert InvalidToken();
        _;
    }
    modifier notOwner(address target) {
        if (target == owner()) revert CantBlacklistOwner();
        _;
    }

    constructor(address op, address ciBTC_, address rbtc_, address rbtc20_, address[] memory tokens) {
        if (op == address(0) || rbtc_ == address(0) || rbtc20_ == address(0) || ciBTC_ == address(0)) {
            revert InvalidZeroAddress();
        }
        for (uint i = 0; i < tokens.length; i++) {
            supportTokens[tokens[i]] = true;
        }
        ciBTC = ciBTC_;
        _rBtc = IRBTC(rbtc_);
        _rBtc20 = IRBTC20(rbtc20_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OP_ROLE, op);
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

    function updateSupportToken(address _token, bool _support) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportTokens[_token] = _support;
        emit UpdateSupportToken(_token, _support);
    }

    function updateManager(address _m) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_m == address(0)) {
            revert InvalidZeroAddress();
        }
        address pre = signer;
        signer = _m;
        emit UpdateManager(pre, _m);
    }
    function updateRBTC(address _m) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_m == address(0)) {
            revert InvalidZeroAddress();
        }
        address pre = address(_rBtc);
        _rBtc = IRBTC(_m);
        emit UpdateRBTC(pre, _m);
    }

    function updateRBTC20(address _m) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_m == address(0)) {
            revert InvalidZeroAddress();
        }
        address pre = address(_rBtc20);
        _rBtc20 = IRBTC20(_m);
        emit UpdateRBTC20(pre, _m);
    }

    function addToBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notOwner(target) {
        _grantRole(CIBTC_STAKER_ROLE, target);
    }

    function removeFromBlacklist(address target) external onlyRole(BLACKLIST_MANAGER_ROLE) notOwner(target) {
        _revokeRole(CIBTC_STAKER_ROLE, target);
    }

    // sofa
    function depositToSofa(address token, uint amount) public onlyRole(OP_ROLE) notZero(amount) notSupportToken(token) {
        if (token == address(0)) {
            _rBtc.deposit{ value: amount }();
        } else {
            TransferHelper.safeApprove(token, address(_rBtc20), amount);
            _rBtc20.deposit(amount);
        }
        emit DepositRBTC(token, msg.sender, amount, block.timestamp);
    }

    // sofa
    function withdrawFromSofa(
        address token,
        uint amount
    ) public onlyRole(OP_ROLE) notZero(amount) notSupportToken(token) {
        // TransferHelper.safeApprove(address(_rBtc), address(_rBtc), amount);
        if (token == address(0)) {
            _rBtc.withdraw(amount);
        } else {
            _rBtc20.withdraw(amount);
        }
        emit WithdrawRBTC(token, msg.sender, amount, block.timestamp);
    }

    function deposit(
        uint256 id,
        address token,
        uint256 amount,
        uint256 shares,
        uint deadline,
        bytes memory signature
    ) public payable nonReentrant notZero(amount) notSupportToken(token) {
        require(block.timestamp <= deadline, "deadline");
        require(!deposits[id], "deposited");
        require(verifySign1(token, id, amount, shares, deadline, signature), "Invalid signature");

        if (hasRole(CIBTC_STAKER_ROLE, msg.sender)) {
            revert OperationNotAllowed();
        }
        if (token == address(0)) {
            if (amount != msg.value) {
                revert InvalidAmount();
            }
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        ICiBtc(ciBTC).mintTo(msg.sender, shares);
        emit Deposit(token, msg.sender, amount, shares, block.timestamp);
    }

    function withdraw(
        address token,
        uint256 id,
        uint256 amount,
        uint256 assets,
        address user,
        uint deadline,
        bytes memory signature
    ) public notSupportToken(token) notZero(assets) {
        require(block.timestamp <= deadline, "deadline");
        require(user == msg.sender, "sender not match");
        require(!withdraws[id], "had claimed");

        require(verifySign(token, id, assets, amount, user, deadline, signature), "Invalid signature");

        IERC20(ciBTC).safeTransferFrom(user, address(this), assets);
        uint _balance = IERC20(ciBTC).balanceOf(address(this));
        ICiBtc(ciBTC).burn(_balance);

        if (token == address(0)) {
            (bool success, ) = msg.sender.call{ value: amount, gas: 10_000 }("");
            require(success, "WITHDRAW_FAILED");
        } else {
            IERC20(token).safeTransfer(user, amount);
        }
        withdraws[id] = true;

        emit Withdrawal(id, user, amount, block.timestamp);
    }

    /// @dev Returns the chain id used by this contract.
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    function verifySign(
        address token,
        uint256 id,
        uint256 assets,
        uint256 amount,
        address account,
        uint256 deadline,
        bytes memory signature
    ) internal view returns (bool verifySuc) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encode(WITHDRAW_TYPEHASH, getChainId(), token, id, assets, amount, account, deadline))
            )
        );

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := and(mload(add(signature, 65)), 255)
        }
        require(
            uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "ECDSA: invalid signature 's' value"
        );
        require(uint8(v) == 27 || uint8(v) == 28, "ECDSA: invalid signature 'v' value");
        address recoveredAddress = ecrecover(digest, v, r, s);

        return recoveredAddress != address(0) && recoveredAddress == signer;
    }

    function verifySign1(
        address token,
        uint256 id,
        uint256 amount,
        uint256 shares,
        uint256 deadline,
        bytes memory signature
    ) internal view returns (bool verifySuc) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encode(DEPOSIT_TYPEHASH, getChainId(), id, token, amount, shares, deadline))
            )
        );

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := and(mload(add(signature, 65)), 255)
        }
        require(
            uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "ECDSA: invalid signature 's' value"
        );
        require(uint8(v) == 27 || uint8(v) == 28, "ECDSA: invalid signature 'v' value");
        address recoveredAddress = ecrecover(digest, v, r, s);

        return recoveredAddress != address(0) && recoveredAddress == signer;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    event Received(address, uint256);
}
