// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ICiBtc is IERC20 {
    function mintTo(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}
