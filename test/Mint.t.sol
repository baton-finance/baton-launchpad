// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BatonLaunchpad.sol";

contract CreateTest is Test {
    address babe = address(0xbabe);
    BatonLaunchpad launchpad;
    Nft nftImplementation;

    function setUp() public {
        // deploy the nft implementation
        nftImplementation = new Nft();

        // deploy the launchpad
        launchpad = new BatonLaunchpad(address(nftImplementation));

        // deal some eth to babe
        deal(babe, 100 ether);
    }

    function generateMerkleRoot() public returns (bytes32) {
        string[] memory inputs = new string[](2);

        inputs[0] = "node";
        inputs[1] = "./test/utils/generate-merkle-root.js";

        bytes memory res = vm.ffi(inputs);
        bytes32 output = abi.decode(res, (bytes32));

        return output;
    }

    function generateMerkleProof(address target) public returns (bytes32[] memory proof) {
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "./test/utils/generate-merkle-proof.js";
        inputs[2] = toHexString(abi.encodePacked(target));

        bytes memory res = vm.ffi(inputs);
        proof = abi.decode(res, (bytes32[]));
    }

    // copied from https://github.com/dmfxyz/murky/blob/main/differential_testing/test/utils/Strings2.sol
    function toHexString(bytes memory input) public pure returns (string memory) {
        require(input.length < type(uint256).max / 2 - 1);
        bytes16 symbols = "0123456789abcdef";
        bytes memory hex_buffer = new bytes(2 * input.length + 2);
        hex_buffer[0] = "0";
        hex_buffer[1] = "x";

        uint256 pos = 2;
        uint256 length = input.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 _byte = uint8(input[i]);
            hex_buffer[pos++] = symbols[_byte >> 4];
            hex_buffer[pos++] = symbols[_byte & 0xf];
        }
        return string(hex_buffer);
    }

    function test_SendsNftsToMinter() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});

        // create the nft
        Nft nft = Nft(launchpad.create("name", "symbol", categories, bytes32(0)));

        // mint the nft
        vm.startPrank(babe);
        uint256 amount = 5;
        nft.mint{value: 1 ether * amount}(uint64(amount), 0, new bytes32[](0));

        // check that the minter owns the 5 nfts
        assertEq(nft.balanceOf(babe), amount);
        for (uint256 i = 0; i < amount; i++) {
            assertEq(nft.ownerOf(i), address(babe));
        }
    }

    function test_UpdatesMintedAmount() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: bytes32(0)});

        // create the nft
        Nft nft = Nft(launchpad.create("name", "symbol", categories, bytes32(0)));

        // mint the nft
        vm.startPrank(babe);
        uint256 amount = 5;
        nft.mint{value: 1 ether * amount}(uint64(amount), 0, new bytes32[](0));

        // check that the minted amount was increased
        assertEq(nft.minted(0), amount);
    }

    function test_RevertIfInvalidMerkleProof() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: keccak256(abi.encode(1111))});

        // create the nft
        Nft nft = Nft(launchpad.create("name", "symbol", categories, bytes32(0)));

        // mint the nft
        vm.expectRevert(Nft.InvalidMerkleProof.selector);
        nft.mint{value: 1 ether}(1, 0, new bytes32[](0));
    }

    function test_MintsWithMerkleProof() public {
        // set the categories
        Nft.Category[] memory categories = new Nft.Category[](1);
        categories[0] = Nft.Category({price: 1 ether, supply: 100, merkleRoot: generateMerkleRoot()});

        // create the nft
        Nft nft = Nft(launchpad.create("name", "symbol", categories, bytes32(0)));

        // mint the nft
        vm.startPrank(babe);
        bytes32[] memory proof = generateMerkleProof(babe);
        uint256 amount = 5;
        nft.mint{value: 1 ether * amount}(uint64(amount), 0, proof);

        // check that the minter owns the 5 nfts
        assertEq(nft.balanceOf(babe), amount);
        for (uint256 i = 0; i < amount; i++) {
            assertEq(nft.ownerOf(i), address(babe));
        }
    }
}
