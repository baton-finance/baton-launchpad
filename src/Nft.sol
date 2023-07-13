// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721AUpgradeable} from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";

contract Nft is ERC721AUpgradeable {
    error TooManyCategories();
    error CategoryDoesNotExist();
    error InvalidEthAmount();
    error InsufficientSupply();
    error InvalidMerkleProof();

    struct Category {
        uint128 price;
        uint128 supply;
        bytes32 merkleRoot;
    }

    Category[] internal _categories;
    mapping(uint8 categoryIndex => uint256) public minted;

    function initialize(string memory name_, string memory symbol_, Category[] memory categories_)
        public
        initializerERC721A
    {
        // check that there is less than 256 categories
        if (categories_.length > 256) revert TooManyCategories();

        // initialize the ERC721AUpgradeable
        __ERC721A_init(name_, symbol_);

        // push all categories
        for (uint256 i = 0; i < categories_.length; i++) {
            _categories.push(categories_[i]);
        }
    }

    function categories(uint8 category) public view returns (Category memory) {
        return _categories[category];
    }

    function mint(uint64 amount, uint8 categoryIndex, bytes32[] calldata proof) public payable {
        // ✅ Checks ✅

        Category memory category = _categories[categoryIndex];

        // check that the price is correct
        if (msg.value != category.price * amount) revert InvalidEthAmount();

        // check that there is enough supply
        if (minted[categoryIndex] + amount > category.supply) revert InsufficientSupply();

        // if the merkle root is not zero then verify that the caller is whitelisted
        if (
            category.merkleRoot != bytes32(0)
                && !MerkleProofLib.verifyCalldata(
                    proof, category.merkleRoot, keccak256(bytes.concat(keccak256(abi.encode(msg.sender))))
                )
        ) {
            revert InvalidMerkleProof();
        }

        // 👷 Effects 👷

        // update the minted amount
        minted[categoryIndex] += amount;

        // mint the tokens
        _safeMint(msg.sender, amount);
    }
}
