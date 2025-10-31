// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../src/NFTMarketplace.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {} //Lo que hacemos con un Mock NFT es simular un NFT con todas sus características solo para testear

    function mint(address to_, uint256 tokenId_) external {
        _mint(to_, tokenId_);
    }
}

//testing
contract NFTMarketPlaceTest is Test {
    //variables
    NFTMarketplace marketplace;
    MockNFT nft;
    address deployer = vm.addr(1);
    address user = vm.addr(2);
    uint256 tokenId = 0;

    function setUp() public {
        vm.startPrank(deployer);
        marketplace = new NFTMarketplace();
        nft = new MockNFT();
        vm.stopPrank();

        vm.startPrank(user);
        nft.mint(user, 0);
        vm.stopPrank();
    }

    function testMintNFT() public view {
        address ownerof = nft.ownerOf(tokenId);
        assert(ownerof == user);
    }
}
