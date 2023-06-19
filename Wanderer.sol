// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "hardhat/console.sol";
// import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev Wanderer is an {ERC721} token, including:
 *
 *  - add token types which is different hero characters
 *  - grants or revokes minter/pauser role 
 *  - token minting or batch minting
 *  - pause/unpause all token transfers
 *  - token ID and URI autogeneration
 *
 * This contract uses {AccessControl} to lock permissioned functions using the
 * different roles - head to its documentation for details.
 *
 * The account that deploys the contract will be granted the minter and pauser
 * roles, as well as the default admin role, which will let it grant both minter
 * and pauser roles to other accounts.
 *
 */
contract Wanderer is 
    AccessControlEnumerable,
    ERC721,
    ERC721Enumerable,
    ERC721Pausable,
    ERC721URIStorage
{
    using Strings for uint256;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    string private _baseTokenURI;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) ERC721(name, symbol) {

        _baseTokenURI = baseTokenURI;

        _setupRole(ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());

        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
    }

    // ----------external functions starts here----------

    /// @dev setBaseURI can update the base url of all the tokens
    function setBaseURI(string memory baseTokenURI) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = baseTokenURI;
    }

    /// @dev safeMint call _safeMint() inside
    function safeMint(address to, uint256 tokenId) external onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);

        _setTokenURI(tokenId, _appendTokenIdSuffix(tokenId));
    }

    /// @dev Grants or revokes MINTER_ROLE
    function setupMinter(address minter, bool enabled) external onlyRole(ADMIN_ROLE) {
        require(minter != address(0), "setupMinter: zero address");
        if (enabled) grantRole(MINTER_ROLE, minter);
        else revokeRole(MINTER_ROLE, minter);   
    }

    /// @dev Grants or revokes PAUSER_ROLE
    function setupPauser(address pauser, bool enabled) external onlyRole(ADMIN_ROLE) {
        require(pauser != address(0), "setupPauser: zero address");
        if (enabled) grantRole(PAUSER_ROLE, pauser);
        else revokeRole(PAUSER_ROLE, pauser);   
    }

    /// @dev getBaseURI returns the current base token URI
    function getBaseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev tokensOfOwner returns the token ids of a owner
    function tokensOfOwner(address _owner) external view returns (uint[] memory) {
        uint tokenCount = balanceOf(_owner);
        uint[] memory tokensId = new uint256[](tokenCount);

        for (uint i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokensId;
    }

    /// @dev Returns true if MINTER
    function isMinter(address minter) external view returns(bool) {
        return hasRole(MINTER_ROLE, minter);
    }

    /// @dev Returns true if PAUSER
    function isPauser(address pauser) external view returns(bool) {
        return hasRole(PAUSER_ROLE, pauser);
    }

    // ----------public functions starts here----------
    /// @dev pause allows admin to pause all token transfers for safety purpose
    function pause() public virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @dev unpause allows admin to unpause all token transfers
    function unpause() public virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    // ----------internal functions starts here----------
        function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function _appendTokenIdSuffix(uint256 _tokenId) internal pure returns(string memory uri){
        uri = string(abi.encodePacked(_tokenId.toString(),".json"));
    }

    // ----------below are overrides required by solidity----------
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Pausable, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC721, ERC721Enumerable, AccessControlEnumerable) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
    
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory) 
    {
        return super.tokenURI(tokenId);
    }
}