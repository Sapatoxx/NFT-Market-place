// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/NFTMarketplace.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {} //Lo que hacemos con un Mock NFT es simular un NFT con todas sus características solo para testear

    function mint(address to_, uint256 tokenId_) external {
        _mint(to_, tokenId_);
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

//testing
contract NFTMarketPlaceTest is Test {
    //variables
    NFTMarketplace marketplace;
    MockNFT nft;
    MockERC20 token;
    address deployer = vm.addr(1);
    address user = vm.addr(2);
    uint256 tokenId = 0;

    function setUp() public {
        vm.startPrank(deployer);
        marketplace = new NFTMarketplace();
        nft = new MockNFT();
        token = new MockERC20();
        marketplace.setTokenAllowance(address(token), true);
        vm.stopPrank();

        vm.startPrank(user);
        nft.mint(user, 0);
        // Aprobación global del marketplace para simplificar los tests positivos
        nft.setApprovalForAll(address(marketplace), true);
        vm.stopPrank();
    }

    function testMintNFT() public view {
        address ownerof = nft.ownerOf(tokenId);
        assert(ownerof == user);
    }

    function testShouldRevertIfPriceIsZero() public {
        vm.startPrank(user);

        vm.expectRevert("Price can not be 0");
        marketplace.listNFT(address(nft), tokenId, 0, address(0));

        vm.stopPrank();
    }

    function testShouldRevertIfNotOwner() public {
        vm.startPrank(user);

        address user2 = vm.addr(3); //en esta funciom tenemos que crear otro usuario ya que el token que nos devuelve la función ownerOf de openzeppelin es un token inexistente para probarr errores
        uint256 tokenId1 = 1;
        nft.mint(user2, tokenId1);
        vm.expectRevert("You are not the owner");
        marketplace.listNFT(address(nft), 1, 1, address(0));

        vm.stopPrank();
    }

    function testListNFTCorrectly() public {
        vm.startPrank(user);

        (address sellerBefore,,,,) = marketplace.listing(address(nft), tokenId);
        marketplace.listNFT(address(nft), tokenId, 1e18, address(0));
        (address sellerAfter,,,,) = marketplace.listing(address(nft), tokenId);

        assert(sellerBefore == address(0) && sellerAfter == user);

        vm.stopPrank();
    }

    function testListShouldRevertIfNotOwner() public {
        vm.startPrank(user);

        (address sellerBefore,,,,) = marketplace.listing(address(nft), tokenId);
        marketplace.listNFT(address(nft), tokenId, 1e18, address(0));
        (address sellerAfter,,,,) = marketplace.listing(address(nft), tokenId);

        vm.stopPrank();
        address user2 = vm.addr(3);

        vm.startPrank(user2);

        vm.expectRevert("You are not the seller");
        marketplace.cancelList(address(nft), tokenId);
        vm.stopPrank();
    }

    function testCancelListSuccessfully() public {
        vm.startPrank(user);


        (address sellerBefore,,,,) = marketplace.listing(address(nft), tokenId);
        marketplace.listNFT(address(nft), tokenId, 1e18, address(0));
        (address sellerAfter,,,,) = marketplace.listing(address(nft), tokenId);

        assert(sellerBefore == address(0) && sellerAfter == user);

        marketplace.cancelList(address(nft), tokenId);
        (address sellerAfter2,,,,) = marketplace.listing(address(nft), tokenId);
        assert(sellerAfter2 == address(0));

        vm.stopPrank();
    }

    function testCanNotBuyUnlistedNFT() public {
        address user2 = vm.addr(3);
        vm.startPrank(user2);

        vm.expectRevert("Listing not exists");
        marketplace.buyNFTWithETH(address(nft), tokenId);

        vm.stopPrank();
    }

    function testERC20ListShouldRevertIfTokenNotAllowed() public {
        // Deshabilitar el token permitido y usar otro no permitido
        MockERC20 token2 = new MockERC20();
        vm.startPrank(user);
        // listing con token no permitido debe revertir
        vm.expectRevert("Payment token not allowed");
        marketplace.listNFT(address(nft), tokenId, 1e18, address(token2));
        vm.stopPrank();
    }

    function testERC20ListNFTCorrectly() public {
        vm.startPrank(user);

        (address sellerBefore,,,,) = marketplace.listing(address(nft), tokenId);
        marketplace.listNFT(address(nft), tokenId, 1e18, address(token));
        (address sellerAfter,,,,) = marketplace.listing(address(nft), tokenId);

        assert(sellerBefore == address(0) && sellerAfter == user);

        vm.stopPrank();
    }

    function testCanNotBuyWithInsufficientFunds() public {
        vm.startPrank(user);

        uint256 price = 1e18;
        (address sellerBefore,,,,) = marketplace.listing(address(nft), tokenId);
        marketplace.listNFT(address(nft), tokenId, price, address(0));
        (address sellerAfter,,,,) = marketplace.listing(address(nft), tokenId);

        assert(sellerBefore == address(0) && sellerAfter == user);

        vm.stopPrank();

        address user2 = vm.addr(3);
        vm.startPrank(user2);
        vm.deal(user2, price);
        vm.expectRevert("Incorrect price");
        marketplace.buyNFTWithETH{value: price - 1}(address(nft), tokenId);

        vm.stopPrank();
    }

    function testERC20CanNotBuyUnlistedNFT() public {
        address user2 = vm.addr(3);
        vm.startPrank(user2);
        vm.expectRevert("Listing not exists");
        marketplace.buyNFTWithERC20(address(nft), tokenId);
        vm.stopPrank();
    }

    function testERC20CanNotBuyWithInsufficientAllowance() public {
        vm.startPrank(user);
        uint256 price = 1e18;
        marketplace.listNFT(address(nft), tokenId, price, address(token));
        vm.stopPrank();

        address user2 = vm.addr(3);
        vm.startPrank(user2);
        token.mint(user2, price);
        // No aprobamos suficiente allowance
        token.approve(address(marketplace), price - 1);
        vm.expectRevert();
        marketplace.buyNFTWithERC20(address(nft), tokenId);
        vm.stopPrank();
    }

    function testERC20CanNotBuyWithInsufficientBalance() public {
        vm.startPrank(user);
        uint256 price = 1e18;
        marketplace.listNFT(address(nft), tokenId, price, address(token));
        vm.stopPrank();

        address user2 = vm.addr(3);
        vm.startPrank(user2);
        // Aprobamos allowance completa pero sin balance suficiente
        token.approve(address(marketplace), price);
        vm.expectRevert();
        marketplace.buyNFTWithERC20(address(nft), tokenId);
        vm.stopPrank();
    }

    function testERC20ShouldBuyCorrectly() public {
        vm.startPrank(user);
        uint256 price = 1e18;
        marketplace.listNFT(address(nft), tokenId, price, address(token));
        vm.stopPrank();

        address buyer = vm.addr(3);
        vm.startPrank(buyer);
        token.mint(buyer, price);
        token.approve(address(marketplace), price);

        uint256 sellerBalanceBefore = token.balanceOf(user);
        uint256 buyerBalanceBefore = token.balanceOf(buyer);
        uint256 contractBalanceBefore = token.balanceOf(address(marketplace));

        (uint256 feeAmount, uint256 sellerAmount) = marketplace.calculateFee(price);

        marketplace.buyNFTWithERC20(address(nft), tokenId);

        uint256 sellerBalanceAfter = token.balanceOf(user);
        uint256 buyerBalanceAfter = token.balanceOf(buyer);
        uint256 contractBalanceAfter = token.balanceOf(address(marketplace));

        // listing eliminado y ownership transferido
        (address afterSeller,,,,) = marketplace.listing(address(nft), tokenId);
        assert(afterSeller == address(0));
        assert(nft.ownerOf(tokenId) == buyer);

        // balances actualizados
        assert(sellerBalanceAfter == sellerBalanceBefore + sellerAmount);
        assert(buyerBalanceAfter == buyerBalanceBefore - price);
        assert(contractBalanceAfter == contractBalanceBefore + feeAmount);

        // fees acumulados en el marketplace
        assert(marketplace.accumulatedFeesERC20(address(token)) == feeAmount);

        vm.stopPrank();
    }

    function testERC20WithdrawFeesWorks() public {
        // Preparar venta para generar fees
        vm.startPrank(user);
        uint256 price = 1e18;
        marketplace.listNFT(address(nft), tokenId, price, address(token));
        vm.stopPrank();

        address buyer = vm.addr(3);
        vm.startPrank(buyer);
        token.mint(buyer, price);
        token.approve(address(marketplace), price);
        (uint256 feeAmount,) = marketplace.calculateFee(price);
        marketplace.buyNFTWithERC20(address(nft), tokenId);
        vm.stopPrank();

        // Retirar fees como owner (deployer)
        vm.startPrank(deployer);
        uint256 ownerBalBefore = token.balanceOf(deployer);
        uint256 contractBalBefore = token.balanceOf(address(marketplace));
        marketplace.withdrawFeesERC20(address(token));
        uint256 ownerBalAfter = token.balanceOf(deployer);
        uint256 contractBalAfter = token.balanceOf(address(marketplace));
        assert(ownerBalAfter == ownerBalBefore + feeAmount);
        assert(contractBalAfter == contractBalBefore - feeAmount);
        assert(marketplace.accumulatedFeesERC20(address(token)) == 0);
        vm.stopPrank();
    }

    function testShouldBuyNFTCorrectly() public {
      vm.startPrank(user);

        uint256 price = 1e18;
        (address sellerBefore,,,,) = marketplace.listing(address(nft), tokenId);
        marketplace.listNFT(address(nft), tokenId, price, address(0));
        (address sellerAfter,,,,) = marketplace.listing(address(nft), tokenId);

        assert(sellerBefore == address(0) && sellerAfter == user);

        vm.stopPrank();

        address user2 = vm.addr(3);
        vm.startPrank(user2);
        vm.deal(user2, price); //le damos menos de lo que cuesta el NFT

        uint256 balanceBefore = address(user).balance;
        address ownerBefore = nft.ownerOf(tokenId);
        (address sellerBefore2,,,,) = marketplace.listing(address(nft), tokenId);
        marketplace.buyNFTWithETH{value: price}(address(nft), tokenId);
        (address sellerAfter2,,,,) = marketplace.listing(address(nft), tokenId);
        address ownerAfter = nft.ownerOf(tokenId);
        uint256 balanceAfter = address(user).balance;

        assert(sellerBefore2 == user && sellerAfter2 == address(0));
        assert(ownerBefore == user && ownerAfter == user2);
        (uint256 feeAmount, uint256 sellerAmount) = marketplace.calculateFee(price);
        assert(balanceAfter == balanceBefore + sellerAmount);

        vm.stopPrank();
    }
}
