// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract NFTMarketplace is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Listing {
        address seller;
        address nftAddress;
        uint256 tokenId;
        uint256 price;
        address paymentToken; // address(0) = ETH, otra address = ERC-20
    }

    // Donde guardaremos los listados
    mapping(address => mapping(uint256 => Listing)) listing;

    // Tokens ERC-20 permitidos para pagos
    mapping(address => bool) public allowedTokens;

    // Fee del marketplace (en basis points: 100 = 1%, 250 = 2.5%, etc.)
    uint256 public marketplaceFee = 250; // 2.5% por defecto

    // Acumulado de fees del owner en ETH
    uint256 public accumulatedFeesETH;

    // Acumulado de fees del owner en tokens ERC-20
    mapping(address => uint256) public accumulatedFeesERC20;

    // Events
    event NFTListed(
        address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price, address paymentToken
    );
    event NFTCanceled(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);
    event NFTSold(
        address indexed buyer,
        address indexed seller,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 price,
        uint256 feeAmount,
        address paymentToken
    );
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawnETH(address indexed owner, uint256 amount);
    event FeesWithdrawnERC20(address indexed owner, address indexed token, uint256 amount);
    event TokenAllowanceUpdated(address indexed token, bool allowed);

    constructor() Ownable(msg.sender) {}

    // Función para permitir/denegar tokens ERC-20 (solo owner)
    function setTokenAllowance(address token_, bool allowed_) external onlyOwner {
        require(token_ != address(0), "Invalid token address");
        allowedTokens[token_] = allowed_;
        emit TokenAllowanceUpdated(token_, allowed_);
    }

    // Función para actualizar el fee del marketplace (solo owner)
    function setMarketplaceFee(uint256 newFee_) external onlyOwner {
        require(newFee_ <= 1000, "Fee cannot exceed 10%");
        uint256 oldFee = marketplaceFee;
        marketplaceFee = newFee_;
        emit FeeUpdated(oldFee, newFee_);
    }

    // Función para que el owner retire sus fees acumulados en ETH
    function withdrawFeesETH() external onlyOwner nonReentrant {
        require(accumulatedFeesETH > 0, "No ETH fees to withdraw");
        uint256 amount = accumulatedFeesETH;
        accumulatedFeesETH = 0;

        (bool success,) = owner().call{value: amount}("");
        require(success, "Withdrawal failed");

        emit FeesWithdrawnETH(owner(), amount);
    }

    // Función para que el owner retire sus fees acumulados en tokens ERC-20
    function withdrawFeesERC20(address token_) external onlyOwner nonReentrant {
        require(accumulatedFeesERC20[token_] > 0, "No token fees to withdraw");
        uint256 amount = accumulatedFeesERC20[token_];
        accumulatedFeesERC20[token_] = 0;

        IERC20(token_).safeTransfer(owner(), amount);

        emit FeesWithdrawnERC20(owner(), token_, amount);
    }

    // List NFTS function - ahora con opción de especificar token de pago
    function listNFT(
        address nftAddress_,
        uint256 tokenId_,
        uint256 price_,
        address paymentToken_ // address(0) para ETH, dirección del token para ERC-20
    ) external nonReentrant {
        require(price_ > 0, "Price can not be 0");

        // Verificar que no existe un listing activo
        require(listing[nftAddress_][tokenId_].price == 0, "NFT already listed");

        // Si no es ETH, verificar que el token está permitido
        if (paymentToken_ != address(0)) {
            require(allowedTokens[paymentToken_], "Payment token not allowed");
        }

        IERC721 nftContract = IERC721(nftAddress_);

        // Verificar que el caller es el owner del NFT
        require(msg.sender == nftContract.ownerOf(tokenId_), "You are not the owner");

        // Verificar que el marketplace tiene aprobación
        require(
            nftContract.isApprovedForAll(msg.sender, address(this))
                || nftContract.getApproved(tokenId_) == address(this),
            "Marketplace not approved"
        );

        Listing memory listing_ = Listing({
            seller: msg.sender,
            nftAddress: nftAddress_,
            tokenId: tokenId_,
            price: price_,
            paymentToken: paymentToken_
        });

        listing[nftAddress_][tokenId_] = listing_;
        emit NFTListed(msg.sender, nftAddress_, tokenId_, price_, paymentToken_);
    }

    // Buy NFTs con ETH
    function buyNFTWithETH(address nftAddress_, uint256 tokenId_) external payable nonReentrant {
        Listing memory listing_ = listing[nftAddress_][tokenId_];
        require(listing_.price > 0, "Listing not exists");
        require(listing_.paymentToken == address(0), "This NFT requires ERC-20 payment");
        require(msg.value == listing_.price, "Incorrect price");

        // Verificar que el seller aún es el owner del NFT
        IERC721 nftContract = IERC721(nftAddress_);
        require(nftContract.ownerOf(tokenId_) == listing_.seller, "Seller is no longer the owner");

        // Verificar aprobación antes de transferir
        require(
            nftContract.isApprovedForAll(listing_.seller, address(this))
                || nftContract.getApproved(listing_.tokenId) == address(this),
            "Marketplace approval revoked"
        );

        // Effects: Borrar el listing ANTES de las interacciones
        delete listing[nftAddress_][tokenId_];

        // Calcular el fee
        uint256 feeAmount = (msg.value * marketplaceFee) / 10000;
        uint256 sellerAmount = msg.value - feeAmount;

        // Acumular fees del owner
        accumulatedFeesETH += feeAmount;

        // Interactions: Transferir el NFT primero (previene reentrancia del seller)
        nftContract.safeTransferFrom(listing_.seller, msg.sender, listing_.tokenId);

        // Transferir ETH al vendedor
        (bool success,) = listing_.seller.call{value: sellerAmount}("");
        require(success, "Transfer failed");

        emit NFTSold(
            msg.sender, listing_.seller, listing_.nftAddress, listing_.tokenId, listing_.price, feeAmount, address(0)
        );
    }

    // Buy NFTs con tokens ERC-20
    function buyNFTWithERC20(address nftAddress_, uint256 tokenId_) external nonReentrant {
        Listing memory listing_ = listing[nftAddress_][tokenId_];
        require(listing_.price > 0, "Listing not exists");
        require(listing_.paymentToken != address(0), "This NFT requires ETH payment");

        address paymentToken = listing_.paymentToken;
        uint256 price = listing_.price;

        // Verificar que el seller aún es el owner del NFT
        IERC721 nftContract = IERC721(nftAddress_);
        require(nftContract.ownerOf(tokenId_) == listing_.seller, "Seller is no longer the owner");

        // Verificar aprobación del NFT
        require(
            nftContract.isApprovedForAll(listing_.seller, address(this))
                || nftContract.getApproved(listing_.tokenId) == address(this),
            "Marketplace approval revoked"
        );

        // Effects: Borrar el listing ANTES de las interacciones
        delete listing[nftAddress_][tokenId_];

        // Calcular el fee
        uint256 feeAmount = (price * marketplaceFee) / 10000;
        uint256 sellerAmount = price - feeAmount;

        // Interactions: Transferir el NFT primero
        nftContract.safeTransferFrom(listing_.seller, msg.sender, listing_.tokenId);

        // Transferir tokens del comprador al vendedor (usando SafeERC20)
        IERC20(paymentToken).safeTransferFrom(msg.sender, listing_.seller, sellerAmount);

        // Transferir fee al contrato
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), feeAmount);

        // Acumular fees del owner
        accumulatedFeesERC20[paymentToken] += feeAmount;

        emit NFTSold(
            msg.sender, listing_.seller, listing_.nftAddress, listing_.tokenId, listing_.price, feeAmount, paymentToken
        );
    }

    // Update listing price
    function updateListingPrice(address nftAddress_, uint256 tokenId_, uint256 newPrice_) external nonReentrant {
        Listing storage listing_ = listing[nftAddress_][tokenId_];
        require(listing_.price > 0, "Listing not exists");
        require(listing_.seller == msg.sender, "You are not the seller");
        require(newPrice_ > 0, "Price can not be 0");

        // Verificar que aún es el owner del NFT
        IERC721 nftContract = IERC721(nftAddress_);
        require(msg.sender == nftContract.ownerOf(tokenId_), "You are no longer the owner");

        listing_.price = newPrice_;

        emit NFTListed(msg.sender, nftAddress_, tokenId_, newPrice_, listing_.paymentToken);
    }

    // Cancel list
    function cancelList(address nftAddress_, uint256 tokenId_) external nonReentrant {
        Listing memory listing_ = listing[nftAddress_][tokenId_];
        require(listing_.price > 0, "Listing not exists");
        require(listing_.seller == msg.sender, "You are not the seller");

        delete listing[nftAddress_][tokenId_];
        emit NFTCanceled(msg.sender, nftAddress_, tokenId_);
    }

    // Función auxiliar para calcular el fee de un precio dado
    function calculateFee(uint256 price_) external view returns (uint256 feeAmount, uint256 sellerAmount) {
        feeAmount = (price_ * marketplaceFee) / 10000;
        sellerAmount = price_ - feeAmount;
    }

    // Función para obtener información de un listado
    function getListing(address nftAddress_, uint256 tokenId_) external view returns (Listing memory) {
        return listing[nftAddress_][tokenId_];
    }

    // Función para verificar si un listing es válido (el vendedor aún es el owner)
    function isListingValid(address nftAddress_, uint256 tokenId_) external view returns (bool) {
        Listing memory listing_ = listing[nftAddress_][tokenId_];
        if (listing_.price == 0) {
            return false;
        }

        IERC721 nftContract = IERC721(nftAddress_);

        // Verificar que el seller aún es el owner
        try nftContract.ownerOf(tokenId_) returns (address currentOwner) {
            if (currentOwner != listing_.seller) {
                return false;
            }
        } catch {
            return false;
        }

        // Verificar que el marketplace tiene aprobación
        bool isApproved = nftContract.isApprovedForAll(listing_.seller, address(this))
            || nftContract.getApproved(tokenId_) == address(this);

        return isApproved;
    }
}
