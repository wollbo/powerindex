// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { DailyIndexConsumer } from "src/DailyIndexConsumer.sol";
import { LocalCREForwarder } from "src/forwarders/LocalCREForwarder.sol";
import { NorthpoleDailyOption } from "src/market/NorthpoleDailyOption.sol";

contract NorthpoleDailyOptionTest is Test {
    DailyIndexConsumer consumer;
    LocalCREForwarder forwarder;
    NorthpoleDailyOption market;

    address seller = address(0xA11CE);
    address buyer  = address(0xB0B);

    // Simulated “CRE sender” address that is allowed to call the forwarder
    address CRE_SENDER = address(0xBEEF);

    bytes32 constant INDEX_ID = keccak256(bytes("NORDPOOL_DAYAHEAD_AVG_V1"));
    bytes32 constant AREA_ID  = keccak256(bytes("NO1"));
    uint32  constant DATE_NUM = 20260125;

    function setUp() public {
        forwarder = new LocalCREForwarder();
        consumer = new DailyIndexConsumer(address(forwarder));
        market = new NorthpoleDailyOption(address(consumer));

        forwarder.setAllowedSender(CRE_SENDER, true);

        vm.deal(seller, 10 ether);
        vm.deal(buyer,  10 ether);
    }

    function _commitIndex(int256 value1e6) internal {
        bytes32 datasetHash = keccak256(abi.encodePacked("demo", value1e6));
        bytes memory report = abi.encode(INDEX_ID, DATE_NUM, AREA_ID, value1e6, datasetHash);

        vm.prank(CRE_SENDER, CRE_SENDER);
        forwarder.forward(address(consumer), hex"", report);
    }


    function test_happyPath_buyerWins_aboveOrEqual() public {
        uint256 premium = 0.1 ether;
        uint256 payout  = 1 ether;
        uint256 strike1e6 = 40_000_000; // 40.0

        // Seller creates offer escrowing payout
        vm.prank(seller);
        uint256 offerId = market.createOffer{ value: payout }(
            INDEX_ID,
            AREA_ID,
            DATE_NUM,
            strike1e6,
            NorthpoleDailyOption.Direction.AboveOrEqual,
            premium
        );

        // Buyer buys and premium transfers immediately to seller
        uint256 sellerBefore = seller.balance;

        vm.prank(buyer);
        market.buy{ value: premium }(offerId);

        assertEq(seller.balance, sellerBefore + premium);

        // Commit index above strike, settle -> buyer gets payout
        _commitIndex(int256(42_420_000));

        uint256 buyerBefore = buyer.balance;
        market.settle(offerId);
        assertEq(buyer.balance, buyerBefore + payout);
    }

    function test_reverts_ifIndexMissing() public {
        uint256 premium = 0.1 ether;
        uint256 payout  = 1 ether;

        vm.prank(seller);
        uint256 offerId = market.createOffer{ value: payout }(
            INDEX_ID,
            AREA_ID,
            DATE_NUM,
            1,
            NorthpoleDailyOption.Direction.AboveOrEqual,
            premium
        );

        vm.prank(buyer);
        market.buy{ value: premium }(offerId);

        vm.expectRevert(NorthpoleDailyOption.IndexNotAvailable.selector);
        market.settle(offerId);
    }

    function test_reverts_doubleSettle() public {
        uint256 premium = 0.1 ether;
        uint256 payout  = 1 ether;

        vm.prank(seller);
        uint256 offerId = market.createOffer{ value: payout }(
            INDEX_ID,
            AREA_ID,
            DATE_NUM,
            1,
            NorthpoleDailyOption.Direction.AboveOrEqual,
            premium
        );

        vm.prank(buyer);
        market.buy{ value: premium }(offerId);

        _commitIndex(2);

        market.settle(offerId);

        vm.expectRevert(NorthpoleDailyOption.Settled.selector);
        market.settle(offerId);
    }
}
