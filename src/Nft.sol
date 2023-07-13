// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721A} from "ERC721A/ERC721A.sol";

contract Nft is ERC721A {
    error TooManyCategories();
    error CategoryDoesNotExist();
    error InvalidEthAmount();
    error InsufficientSupply();

    struct Category {
        uint128 price;
        uint64 supply;
        uint64 minted;
    }

    Category[] public categories;

    constructor(string memory _name, string memory _symbol, Category[] memory _categories) ERC721A(_name, _symbol) {
        // check that there is less than 256 categories
        if (_categories.length > 256) revert TooManyCategories();

        // push all categories
        for (uint256 i = 0; i < _categories.length; i++) {
            categories.push(_categories[i]);
        }
    }

    function mint(uint64 amount, uint8 category) public payable {
        // ✅ Checks ✅

        // check that the category exists
        if (category >= categories.length) revert CategoryDoesNotExist();

        // check that the price is correct
        if (msg.value != categories[category].price * amount) revert InvalidEthAmount();

        // check that there is enough supply
        if (categories[category].minted + amount > categories[category].supply) revert InsufficientSupply();

        // 👷 Effects 👷

        // update the minted amount
        categories[category].minted += amount;

        // mint the tokens
        _safeMint(msg.sender, amount);
    }
}
