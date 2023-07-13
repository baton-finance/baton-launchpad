// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Nft} from "./Nft.sol";

contract BatonLaunchpad {
    function create(string calldata name, string calldata symbol, Nft.Category[] calldata categories) public {
        new Nft(name, symbol, categories);
    }
}
