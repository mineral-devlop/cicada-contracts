// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SingleAdminAccessControl } from "./SingleAdminAccessControl.sol";

contract CiBtc is ERC20, SingleAdminAccessControl {
    bytes32 private constant MINT_ROLE = keccak256("MINT_ROLE");

    event AdminTransfer(address pre, address indexed newAdmin);
    error InvalidZeroAddress();

    constructor(address _admin, address _mintRole) ERC20("Cicada finance", "ciBTC") {
        if (_admin == address(0) || _mintRole == address(0)) {
            revert InvalidZeroAddress();
        }
        _grantRole(MINT_ROLE, _mintRole);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function addMintRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINT_ROLE, _account);
    }

    function removeMintRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINT_ROLE, _account);
    }

    function mintTo(address to, uint256 amount) external onlyRole(MINT_ROLE) {
        _mint(to, amount);
    }
    function burn(uint256 amount) external onlyRole(MINT_ROLE) {
        _burn(msg.sender, amount);
    }
}
