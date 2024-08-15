// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IRBTC is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
