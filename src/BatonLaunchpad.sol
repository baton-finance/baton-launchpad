// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibClone} from "solady/utils/LibClone.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Nft} from "./Nft.sol";

contract BatonLaunchpad is Ownable {
    using LibClone for address;

    address public nftImplementation;

    constructor(address _nftImplementation) {
        _initializeOwner(msg.sender);
        setNftImplementation(_nftImplementation);
    }

    function create(string calldata name, string calldata symbol, Nft.Category[] calldata categories, bytes32 salt)
        public
        returns (Nft nft)
    {
        // deploy the nft
        nft = Nft(payable(nftImplementation.cloneDeterministic(salt)));

        // initialize the nft
        nft.initialize(name, symbol, categories);
    }

    function setNftImplementation(address _nftImplementation) public onlyOwner {
        nftImplementation = _nftImplementation;
    }
}
