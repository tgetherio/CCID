// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator, IRouterClient, LinkToken} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

// Import CCID contracts
import {CCIDReceiver} from "../src/CCIDReceiver.sol";
import {StorageReceiver} from "../src/StorageReceiver.sol";
import {CCIDStorage} from "../src/CCIDStorage.sol";
import {CCIDIndividualManager} from "../src/CCIDIndividualManager.sol";
import {StorageSender} from "../src/StorageSender.sol";
import {IndividualSender} from "../src/IndividualSender.sol";

contract CCIDIndividualsTest is Test {
    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    CCIPLocalSimulator public ccipLocalSimulator;

    uint64 public baseChainSelector;
    uint64 public xChainSelector;
    IRouterClient public baseRouter;
    IRouterClient public xChainRouter;
    LinkToken public linkToken;

    CCIDStorage public ccidStorage;
    StorageReceiver public storageReceiver;
    CCIDIndividualManager public individualManager;
    StorageSender public storageSender;
    CCIDReceiver public ccidReceiver;
    IndividualSender public individualSender;

    address public creator = address(0x123);
    address public newMember = address(0x456);

    /*//////////////////////////////////////////////////////////////
                               SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Deploy the CCIP Local Simulator
        ccipLocalSimulator = new CCIPLocalSimulator();

        // Get chain simulation details
        (uint64 chainSelectorA, IRouterClient routerA, IRouterClient routerB, , LinkToken link,,) =
            ccipLocalSimulator.configuration();

        // Assign base and external chain selectors
        baseChainSelector = chainSelectorA; // Base chain (CCIDStorage)
        xChainSelector = chainSelectorA;    // External chain (User interactions)

        baseRouter = routerA;
        xChainRouter = routerB;
        linkToken = link;

        /* ---------------- Deploy Base Chain Contracts ---------------- */
        ccidStorage = new CCIDStorage();
        storageSender = new StorageSender(address(baseRouter), address(linkToken)); // Broadcasts data

        /* ---------------- Deploy External Chain Contracts ---------------- */
        individualSender = new IndividualSender(
            address(xChainRouter), 
            address(linkToken), 
            baseChainSelector, 
            address(ccidReceiver)
        );
        storageReceiver = new StorageReceiver(address(xChainRouter)); // Stores received updates
        individualManager = new CCIDIndividualManager(address(ccidStorage), address(storageReceiver));
        ccidReceiver = new CCIDReceiver(address(baseRouter),address(individualManager), chainSelectorA ); // Processes messages on base chain
        ccidStorage.updateManagers(address(individualManager), address(0)); // add commuinity later
    }

    /*//////////////////////////////////////////////////////////////
                      TESTING INDIVIDUAL CCID ACTIONS
    //////////////////////////////////////////////////////////////*/

    function testCreateCCID() public {

        vm.prank(creator);
        bytes32 ccid = individualManager.createCCID();

        // Verify CCID exists with correct creator
        assertEq(ccidStorage.getCCIDCreator(ccid), creator);
    }

    // function testAddAndRemoveAddress() public {
    //     bytes32 ccid = keccak256(abi.encodePacked("testCCID"));

    //     vm.prank(creator);
    //     ccidStorage.createIndividualCCID(ccid, creator);

    //     vm.prank(creator);
    //     individualManager.linkAddress(ccid, 1, newMember);

    //     assertEq(ccidStorage.getCCIDForAddress(1, newMember), ccid);

    //     vm.prank(creator);
    //     individualManager.unlinkAddress(ccid, 1, newMember);

    //     assertEq(ccidStorage.getCCIDForAddress(1, newMember), bytes32(0));
    // }

    /*//////////////////////////////////////////////////////////////
                      TESTING CROSS-CHAIN UPDATES
    //////////////////////////////////////////////////////////////*/

   function testStorageSync() public {
            bytes32 ccid = keccak256(abi.encodePacked("testCCID"));

            // Step 1: Create CCID on Base Chain
            vm.prank(creator);
            individualManager.createCCID();

            // Check event was emitted
            vm.expectEmit(true, true, true, true);
            emit CCIDStorage.IndividualCreated(ccid, creator);

            // Step 2: Add address, triggering CCIP sync
            vm.prank(creator);
            individualManager.linkAddress(ccid, 1, newMember);

            // Verify storage is updated on base chain
            assertEq(ccidStorage.getCCIDForAddress(1, newMember), ccid);

            // Step 3: Verify storage is updated on External Chain
            assertEq(storageReceiver.getCCIDForAddress(1, newMember), ccid);
        }
//     /*//////////////////////////////////////////////////////////////
//                       FULL CROSS-CHAIN CCID TEST
//     //////////////////////////////////////////////////////////////*/

//     function testFullCCIDFlow() public {
//         bytes32 ccid = keccak256(abi.encodePacked("fullCCIDTest"));

//         vm.prank(creator);
//         ccidStorage.createIndividualCCID(ccid, creator);

//         vm.prank(creator);
//         individualManager.linkAddress(ccid, 1, newMember);
//         storageSender.sendStorageUpdate(ccid, 1, newMember, true, StorageSender.PayFeesIn.Native);

//         ccipLocalSimulator.routeMessage(baseChainSelector, xChainSelector);
//         assertEq(storageReceiver.getCCIDForAddress(1, newMember), ccid);

//         vm.prank(creator);
//         individualManager.unlinkAddress(ccid, 1, newMember);
//         storageSender.sendStorageUpdate(ccid, 1, newMember, false, StorageSender.PayFeesIn.Native);

//         ccipLocalSimulator.routeMessage(baseChainSelector, xChainSelector);
//         assertEq(storageReceiver.getCCIDForAddress(1, newMember), bytes32(0));
//     }
}
