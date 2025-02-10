// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CCIDStorage.sol";

/**
 * @title IndividualCCID
 * @notice Manages individual user identities, linking and unlinking addresses across chains.
 *         Relies on a Cross-Chain Hub for message forwarding.
 */
contract IndividualCCID is Ownable {
    CCIDStorage public ccidStorage;
    address public crossChainHub;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event AddressLinked(bytes32 indexed ccid, uint256 chainId, address indexed linkedAddress);
    event AddressUnlinked(bytes32 indexed ccid, uint256 chainId, address indexed linkedAddress);

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract with the CCID storage contract and Cross-Chain Hub address.
     * @param _ccidStorage Address of the CCID storage contract.
     * @param _crossChainHub Address of the Cross-Chain Hub.
     */
    constructor(address _ccidStorage, address _crossChainHub) Ownable(msg.sender) {
        require(_ccidStorage != address(0) && _crossChainHub != address(0), "Invalid addresses");

        ccidStorage = CCIDStorage(_ccidStorage);
        crossChainHub = _crossChainHub;
    }

    /*//////////////////////////////////////////////////////////////
                           MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensures that only the Cross-Chain Hub can call certain functions.
     */
    modifier onlyCrossChainHub() {
        require(msg.sender == crossChainHub, "Unauthorized: Caller is not the Cross-Chain Hub");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                      CROSS-CHAIN MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Links an address to a CCID, called only by the Cross-Chain Hub.
     * @param ccid The CCID to link the address to.
     * @param chainId The originating chain ID.
     * @param linkedAddress The address being linked.
     */
    function processLinkAddress(bytes32 ccid, uint256 chainId, address linkedAddress) external onlyCrossChainHub {
        ccidStorage.linkAddress(ccid, chainId, linkedAddress);
        emit AddressLinked(ccid, chainId, linkedAddress);
    }

    /**
     * @notice Unlinks an address from a CCID, called only by the Cross-Chain Hub.
     * @param ccid The CCID to unlink from.
     * @param chainId The originating chain ID.
     */
    function processUnlinkAddress(bytes32 ccid, uint256 chainId) external onlyCrossChainHub {
        ccidStorage.unlinkAddress(ccid, chainId);
        emit AddressUnlinked(ccid, chainId, ccidStorage.getCCIDForAddress(chainId, msg.sender));
    }

    /*//////////////////////////////////////////////////////////////
                       ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the Cross-Chain Hub contract.
     * @param _newHub The new Cross-Chain Hub contract address.
     */
    function updateCrossChainHub(address _newHub) external onlyOwner {
        require(_newHub != address(0), "Invalid address");
        crossChainHub = _newHub;
    }
}
