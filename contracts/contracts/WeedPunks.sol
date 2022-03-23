// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./ERC721A.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";


contract WeedPunks is ERC721A, Ownable, ReentrancyGuard, Pausable {
    using Strings for uint256;
    string public baseUri = "";
    uint256 public supply = 10000;
    string public extension = ".json";  

    bool public freeclaimLive;
    bool public greenlistLive;
    address payable public payoutAddress;
    bytes32 public greenlistMerkleRoot;

    struct Config {
        uint256 freeClaimPrice;
        uint256 mintPrice;
        uint256 glPrice;
        uint256 maxMint;
        uint256 maxfreeClaim;
        uint256 maxgreenlist;
        uint256 maxfreeClaimPerTx;
        uint256 maxgreenlistPerTx;
        uint256 maxMintPerTx;
    }

    struct LimitPerWallet {
        uint256 mint;
        uint256 greenlist;
        uint256 freeclaim;
    }

    Config public config;
    
    mapping(address => LimitPerWallet) limitPerWallet;
    mapping(address => bool) admins;

    event GreenlistLive(bool live);
    event FreeClaimLive(bool live);

    constructor() ERC721A("WeedPunks", "WP") { 
        _pause(); 
        config.freeClaimPrice = 0.000 ether; 
        config.mintPrice = 0.10 ether;
        config.glPrice = 0.042 ether;
        config.maxMint = 10;
        config.maxgreenlist = 10;
        config.maxfreeClaim = 1;
        config.maxfreeClaimPerTx = 1;
        config.maxgreenlistPerTx = 10;
        config.maxMintPerTx = 10;
    }

        /**
     * @dev validates merkleProof
     */
    modifier isValidMerkleProof(bytes32[] calldata merkleProof, bytes32 root) {
        require(
            MerkleProof.verify(
                merkleProof,
                root,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "Address does not exist in list"
        );
        _;
    }


    function greenlistMint(uint256 count, bytes32[] calldata proof) external payable isValidMerkleProof(proof, greenlistMerkleRoot) nonReentrant notBots {
        require(greenlistLive, "Not live");
        require(count <= config.maxgreenlistPerTx, "Exceeds max");
        require(limitPerWallet[msg.sender].greenlist + count <= config.maxgreenlist, "Exceeds max");
        require(msg.value >= config.glPrice * count, "invalid price");
        limitPerWallet[msg.sender].greenlist += count;
        _callMint(count, msg.sender);        
    }

    function mint(uint256 count) external payable nonReentrant whenNotPaused notBots {       
        require(count <= config.maxMintPerTx, "Exceeds max");
        require(limitPerWallet[msg.sender].mint + count <= config.maxMint, "Exceeds max");         
        require(msg.value >= config.mintPrice * count, "invalid price");
        limitPerWallet[msg.sender].mint += count;
        _callMint(count, msg.sender);        
    }

    function freeClaimMint(uint256 count) external payable nonReentrant whenNotPaused notBots {       
        require (freeclaimLive, "Not live");
        require(count <= config.maxfreeClaimPerTx, "Exceeds max");
        require(limitPerWallet[msg.sender].freeclaim + count <= config.maxfreeClaim, "Exceeds max");         
        require(msg.value >= config.freeClaimPrice * count, "invalid price");
        limitPerWallet[msg.sender].freeclaim += count;
        _callMint(count, msg.sender);        
    }


    modifier notBots {        
        require(_msgSender() == tx.origin, "no bots");
        _;
    }

    function adminMint(uint256 count, address to) external adminOrOwner {
        _callMint(count, to);
    }

    function _callMint(uint256 count, address to) internal {        
        uint256 total = totalSupply();
        require(count > 0, "Count is 0");
        require(total + count <= supply, "Sold out");
        _safeMint(to, count);
    }

    function burn(uint256 tokenId) external {
        TokenOwnership memory prevOwnership = ownershipOf(tokenId);

        bool isApprovedOrOwner = (_msgSender() == prevOwnership.addr ||
            isApprovedForAll(prevOwnership.addr, _msgSender()) ||
            getApproved(tokenId) == _msgSender());

        require(isApprovedOrOwner, "Not approved");
        _burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "ERC721Metadata: Nonexistent token");
        string memory currentBaseURI = baseUri;
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        extension
                    )
                )
                : "";
    }

    function setExtension(string memory _extension) external adminOrOwner {
        extension = _extension;
    }

    function setUri(string memory _uri) external adminOrOwner {
        baseUri = _uri;
    }

    function setPaused(bool _paused) external adminOrOwner {
        if(_paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    function toggleGreenlistLive() external adminOrOwner {
        bool isLive = !greenlistLive;
        greenlistLive = isLive;
        emit GreenlistLive(isLive);
    }
    function toggleFreeClaimLive() external adminOrOwner {
        bool isLive = !freeclaimLive;
        freeclaimLive = isLive;
        emit FreeClaimLive(isLive);
    }

    function setGreenlistMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        greenlistMerkleRoot = merkleRoot;
    }


    function setSupply(uint256 _supply) external adminOrOwner {
        supply = _supply;
    }



    function setConfig(Config memory _config) external adminOrOwner {
        config = _config;
    }

    function setpayoutAddress(address payable _payoutAddress) external adminOrOwner {
        payoutAddress = _payoutAddress;
    }
     
    function withdraw() external adminOrOwner {
        (bool success, ) = payoutAddress.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function addAdmin(address _admin) external adminOrOwner {
        admins[_admin] = true;
    }

    function removeAdmin(address _admin) external adminOrOwner {
        delete admins[_admin];
    }

    modifier adminOrOwner() {
        require(msg.sender == owner() || admins[msg.sender], "Unauthorized");
        _;
    }
}