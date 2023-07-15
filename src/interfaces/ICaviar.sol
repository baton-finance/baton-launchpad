// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICaviar {
    function pairs(address nft, address baseToken, bytes32 merkleRoot) external view returns (address);
    function create(address nft, address baseToken, bytes32 merkleRoot) external returns (IPair);
}

interface IPair {
    struct Message {
        bytes32 id;
        bytes payload;
        // The UNIX timestamp when the message was signed by the oracle
        uint256 timestamp;
        // ECDSA signature or EIP-2098 compact signature
        bytes signature;
    }

    function nftAdd(
        uint256 baseTokenAmount,
        uint256[] calldata tokenIds,
        uint256 minLpTokenAmount,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 deadline,
        bytes32[][] calldata proofs,
        Message[] calldata messages
    ) external payable returns (uint256 lpTokenAmount);

    function addQuote(uint256 baseTokenAmount, uint256 fractionalTokenAmount, uint256 lpTokenSupply)
        external
        view
        returns (uint256);

    function lpToken() external view returns (ILpToken);
}

interface ILpToken {
    function totalSupply() external view returns (uint256);
}
