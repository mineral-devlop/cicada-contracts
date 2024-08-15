// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MBtc is ERC20 {
    error InvalidZeroAddress();

    constructor() ERC20("test M-BTC", "M-BTC") {
        _mint(msg.sender, 10 ** 8 * 1e18);
    }
}
