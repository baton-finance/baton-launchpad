// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibClone} from "solady/utils/LibClone.sol";
import {Nft} from "./Nft.sol";

contract BatonLaunchpad {
    using LibClone for address;

    address public nftImplementation;

    constructor(address _nftImplementation) {
        setNftImplementation(_nftImplementation);
    }

    function create(string calldata name, string calldata symbol, Nft.Category[] calldata categories, bytes32 salt)
        public
        returns (Nft nft)
    {
        nft = Nft(payable(nftImplementation.cloneDeterministic(salt)));
    }

    function setNftImplementation(address _nftImplementation) public {
        nftImplementation = _nftImplementation;
    }
}
