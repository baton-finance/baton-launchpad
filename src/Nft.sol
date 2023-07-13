// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721AUpgradeable} from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";

contract Nft is ERC721AUpgradeable {
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

    function initialize(string memory _name, string memory _symbol, Category[] memory _categories)
        public
        initializerERC721A
    {
        // check that there is less than 256 categories
        if (_categories.length > 256) revert TooManyCategories();

        // initialize the ERC721AUpgradeable
        __ERC721A_init(_name, _symbol);

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
