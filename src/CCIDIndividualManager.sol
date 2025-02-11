// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CCIDStorage} from "./CCIDStorage.sol";

/**
 * @title CCIDIndividualManager
 * @notice Handles linking, unlinking, and approving addresses for Individual CCIDs, with both local and cross-chain execution.
 */
contract CCIDIndividualManager is Ownable {
    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    CCIDStorage public ccidStorage;
    address public receiverContract;

    // Mapping: CCID => (Address => Approved Status)
    mapping(bytes32 => mapping(address => bool)) public isApproved;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event CCIDCreated(bytes32 indexed ccid, address indexed creator);
    event AddressLinked(bytes32 indexed ccid, uint256 chainId, address indexed linkedAddress);
    event AddressUnlinked(bytes32 indexed ccid, uint256 chainId, address indexed linkedAddress);
    event ReceiverUpdated(address indexed newReceiver);
    event AddressApproved(bytes32 indexed ccid, address indexed approver, address indexed approvedAddress);
    event AddressRevoked(bytes32 indexed ccid, address indexed revoker, address indexed revokedAddress);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _ccidStorage, address _receiverContract) Ownable(msg.sender) {
        ccidStorage = CCIDStorage(_ccidStorage);
        receiverContract = _receiverContract;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the CCIDReceiver contract that can modify this manager.
     * @param _receiverContract The new authorized receiver contract.
     */
    function updateReceiver(address _receiverContract) external onlyOwner {
        receiverContract = _receiverContract;
        emit ReceiverUpdated(_receiverContract);
    }

    /*//////////////////////////////////////////////////////////////
                      APPROVAL SYSTEM
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves an address to add/remove addresses in a specific CCID.
     * @dev Can only be called by an already approved address.
     * @param ccid The CCID where the approval applies.
     * @param newAddress The address to be approved.
     */
    function approveAddress(bytes32 ccid, address newAddress) external {
        require(isApproved[ccid][msg.sender] || msg.sender == ccidStorage.getCCIDCreator(ccid), "Not authorized to approve");
        isApproved[ccid][newAddress] = true;
        emit AddressApproved(ccid, msg.sender, newAddress);
    }

    /**
     * @notice Revokes an address's ability to add/remove members in a specific CCID.
     * @dev Can only be called by an already approved address.
     * @param ccid The CCID where the revocation applies.
     * @param targetAddress The address to be revoked.
     */
    function revokeAddress(bytes32 ccid, address targetAddress) external {
        require(isApproved[ccid][msg.sender], "Not authorized to revoke");
        require(targetAddress != ccidStorage.getCCIDCreator(ccid), "Cannot revoke creator");

        isApproved[ccid][targetAddress] = false;
        emit AddressRevoked(ccid, msg.sender, targetAddress);
    }

    /*//////////////////////////////////////////////////////////////
                      LOCAL EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new Individual CCID.
     * @dev This must be done on Chain A (our base chain).
     */
    function createCCID() external returns (bytes32) {
        bytes32 ccid = ccidStorage.createIndividualCCID(msg.sender);
        isApproved[ccid][msg.sender] = true; // Creator auto-approved
        emit CCIDCreated(ccid, msg.sender);
        return ccid;
    }

    /**
     * @notice Links a new address to an Individual CCID (local execution).
     * @dev Requires approval from an already approved address.
     * @param ccid The Individual CCID to link the address to.
     * @param chainId The chain ID where the address exists.
     * @param linkedAddress The address being linked.
     */
    function linkAddress(bytes32 ccid, uint256 chainId, address linkedAddress) external {
        require(isApproved[ccid][msg.sender], "Not authorized to link");
        ccidStorage.linkAddress(ccid, chainId, linkedAddress);
        emit AddressLinked(ccid, chainId, linkedAddress);
    }

    /**
     * @notice Unlinks an address from an Individual CCID (local execution).
     * @dev Requires approval from an already approved address.
     * @param ccid The Individual CCID to unlink from.
     * @param chainId The chain ID where the address exists.
     * @param linkedAddress The address being removed.
     */
    function unlinkAddress(bytes32 ccid, uint256 chainId, address linkedAddress) external {
        require(isApproved[ccid][msg.sender], "Not authorized to unlink");
        require(linkedAddress != ccidStorage.getCCIDCreator(ccid), "Cannot remove creator");

        ccidStorage.unlinkAddress(ccid, chainId, linkedAddress);
        emit AddressUnlinked(ccid, chainId, linkedAddress);
    }

    /*//////////////////////////////////////////////////////////////
                      CROSS-CHAIN EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Links a new address to an Individual CCID (cross-chain execution).
     * @dev Only callable by `CCIDReceiver.sol` when receiving CCIP messages.
     * @param ccid The Individual CCID to link the address to.
     * @param chainId The chain ID where the address exists.
     * @param linkedAddress The address being linked.
     */
    function linkAddressFromReceiver(bytes32 ccid, uint256 chainId, address linkedAddress) external {
        require(msg.sender == receiverContract, "Only receiver can call");
        require(isApproved[ccid][linkedAddress], "Address must be approved before linking");

        ccidStorage.linkAddress(ccid, chainId, linkedAddress);
        emit AddressLinked(ccid, chainId, linkedAddress);
    }

    /**
     * @notice Unlinks an address from an Individual CCID (cross-chain execution).
     * @dev Only callable by `CCIDReceiver.sol` when receiving CCIP messages.
     * @param ccid The Individual CCID to unlink from.
     * @param chainId The chain ID where the address exists.
     * @param linkedAddress The address being removed.
     */
    function unlinkAddressFromReceiver(bytes32 ccid, uint256 chainId, address linkedAddress) external {
        require(msg.sender == receiverContract, "Only receiver can call");
        require(isApproved[ccid][linkedAddress], "Address must be approved before unlinking");
        require(linkedAddress != ccidStorage.getCCIDCreator(ccid), "Cannot remove creator");

        ccidStorage.unlinkAddress(ccid, chainId, linkedAddress);
        emit AddressUnlinked(ccid, chainId, linkedAddress);
    }

        /**
     * @notice Approves an address to add/remove addresses in a specific CCID (cross-chain execution).
     * @dev Only callable by `CCIDReceiver.sol` when receiving CCIP messages.
     * @param ccid The CCID where the approval applies.
     * @param approver The address that initiated the approval.
     * @param approvedAddress The address being approved.
     */
    function approveAddressFromReceiver(bytes32 ccid, address approver, address approvedAddress) external {
        require(msg.sender == receiverContract, "Only receiver can call");
        require(isApproved[ccid][approver] || approver == ccidStorage.getCCIDCreator(ccid), "Not authorized to approve");

        isApproved[ccid][approvedAddress] = true;
        emit AddressApproved(ccid, approver, approvedAddress);
    }

    /**
     * @notice Revokes an address's ability to modify a CCID (cross-chain execution).
     * @dev Only callable by `CCIDReceiver.sol` when receiving CCIP messages.
     * @param ccid The CCID where the revocation applies.
     * @param revoker The address that initiated the revocation.
     * @param revokedAddress The address being revoked.
     */
    function revokeAddressFromReceiver(bytes32 ccid, address revoker, address revokedAddress) external {
        require(msg.sender == receiverContract, "Only receiver can call");
        require(isApproved[ccid][revoker], "Not authorized to revoke");
        require(revokedAddress != ccidStorage.getCCIDCreator(ccid), "Cannot revoke creator");

        isApproved[ccid][revokedAddress] = false;
        emit AddressRevoked(ccid, revoker, revokedAddress);
    }

}
