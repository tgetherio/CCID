// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CCIDStorage
 * @notice Stores Cross Chain Identity (CCID) information and restricts modifications to approved contracts.
 */
contract CCIDStorage is Ownable {
    /*//////////////////////////////////////////////////////////////
                           DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/
    
    enum CCIDType { INDIVIDUAL, COMMUNITY }

    struct Identity {
        CCIDType ccidType;                // Type of CCID: Individual or Community
        address creator;                  // Who created this CCID
        uint256 createdAt;                // Timestamp of creation
        mapping(uint256 => address) linkedAddresses; // chainId => address
        uint256 lastUpdated;
    }

    mapping(bytes32 => Identity) private identities;   // ccid => Identity struct
    mapping(bytes32 => bytes32) public addressToCCID;  // keccak256(chainId, addr) => ccid

    // Approved contracts that can modify CCID data
    mapping(address => bool) public approvedContracts;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event CCIDCreated(bytes32 indexed ccid, CCIDType ccidType, address indexed creator);
    event AddressLinked(bytes32 indexed ccid, uint256 chainId, address indexed linkedAddress);
    event AddressUnlinked(bytes32 indexed ccid, uint256 chainId, address indexed linkedAddress);
    event ApprovedContractUpdated(address indexed contractAddress, bool isApproved);

    /*//////////////////////////////////////////////////////////////
                          MODIFIER
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensures that only approved contracts can modify CCID data.
     */
    modifier onlyApproved() {
        require(approvedContracts[msg.sender], "Unauthorized: Caller is not an approved contract");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                      OWNER ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the owner to approve or remove contracts that can modify CCID data.
     * @param contractAddress The address of the contract to approve/revoke.
     * @param isApproved Whether to approve (true) or revoke (false).
     */
    function updateApprovedContract(address contractAddress, bool isApproved) external onlyOwner {
        approvedContracts[contractAddress] = isApproved;
        emit ApprovedContractUpdated(contractAddress, isApproved);
    }

    /*//////////////////////////////////////////////////////////////
                      CCID DATA MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new CCID.
     * @dev Only an approved contract (CCID Registry, Individual CCID, or Community CCID contract) can call this.
     * @param ccid The unique identifier for the CCID.
     * @param ccidType Whether this is an INDIVIDUAL or COMMUNITY CCID.
     * @param creator The address of the entity that created this CCID.
     */
    function createCCID(bytes32 ccid, CCIDType ccidType, address creator) external onlyApproved {
        require(identities[ccid].createdAt == 0, "CCID already exists");

        Identity storage identity = identities[ccid];
        identity.ccidType = ccidType;
        identity.creator = creator;
        identity.createdAt = block.timestamp;
        identity.lastUpdated = block.timestamp;

        emit CCIDCreated(ccid, ccidType, creator);
    }

    /**
     * @notice Links an address to a CCID on a specific chain.
     * @dev Only approved contracts can call this.
     * @param ccid The CCID to link the address to.
     * @param chainId The chain ID where the address exists.
     * @param linkedAddress The address being linked.
     */
    function linkAddress(bytes32 ccid, uint256 chainId, address linkedAddress) external onlyApproved {
        require(identities[ccid].createdAt != 0, "CCID does not exist");
        require(addressToCCID[_makeAddressKey(chainId, linkedAddress)] == 0, "Address already linked");

        addressToCCID[_makeAddressKey(chainId, linkedAddress)] = ccid;
        identities[ccid].linkedAddresses[chainId] = linkedAddress;
        identities[ccid].lastUpdated = block.timestamp;

        emit AddressLinked(ccid, chainId, linkedAddress);
    }

    /**
     * @notice Unlinks an address from a CCID on a specific chain.
     * @dev Only approved contracts can call this.
     * @param ccid The CCID to unlink from.
     * @param chainId The chain ID where the address exists.
     */
    function unlinkAddress(bytes32 ccid, uint256 chainId) external onlyApproved {
        require(identities[ccid].createdAt != 0, "CCID does not exist");

        address linkedAddr = identities[ccid].linkedAddresses[chainId];
        require(linkedAddr != address(0), "Address not linked");

        bytes32 addrKey = _makeAddressKey(chainId, linkedAddr);
        delete addressToCCID[addrKey];
        delete identities[ccid].linkedAddresses[chainId];
        identities[ccid].lastUpdated = block.timestamp;

        emit AddressUnlinked(ccid, chainId, linkedAddr);
    }

    /*//////////////////////////////////////////////////////////////
                      VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns CCID type (INDIVIDUAL or COMMUNITY).
     * @param ccid The CCID being queried.
     */
    function getCCIDType(bytes32 ccid) external view returns (CCIDType) {
        require(identities[ccid].createdAt != 0, "CCID does not exist");
        return identities[ccid].ccidType;
    }

    /**
     * @notice Returns the CCID linked to a specific address on a given chain.
     * @param chainId The chain ID of the address.
     * @param addr The address being queried.
     */
    function getCCIDForAddress(uint256 chainId, address addr) external view returns (bytes32) {
        return addressToCCID[_makeAddressKey(chainId, addr)];
    }

    /**
     * @notice Checks if a contract is an approved modifier of CCID data.
     * @param contractAddress The contract address being queried.
     */
    function isApprovedContract(address contractAddress) external view returns (bool) {
        return approvedContracts[contractAddress];
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL UTILITIES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Generates a unique key for an address on a given chain.
     * @param chainId The chain ID.
     * @param addr The address.
     */
    function _makeAddressKey(uint256 chainId, address addr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(chainId, addr));
    }
}
