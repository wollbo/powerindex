// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IIndexConsumer } from "../interfaces/IIndexConsumer.sol";

contract NorthpoleDailyOption {
    enum Direction { AboveOrEqual, Below }

    struct Offer {
        address seller;
        address buyer;
        bytes32 indexId;
        bytes32 areaId;
        uint32 yyyymmdd;
        uint256 strike1e6;
        Direction direction;
        uint256 premiumWei;
        uint256 payoutWei;
        bool cancelled;
        bool settled;
    }

    IIndexConsumer public immutable consumer;

    uint256 public nextOfferId;
    mapping(uint256 => Offer) public offers;

    error NotSeller();
    error AlreadyPurchased();
    error Cancelled();
    error Settled();
    error InvalidValue();
    error IndexNotAvailable();
    error NotAllowed();

    event OfferCreated(
        uint256 indexed offerId,
        address indexed seller,
        bytes32 indexed indexId,
        bytes32 areaId,
        uint32 yyyymmdd,
        uint256 strike1e6,
        Direction direction,
        uint256 premiumWei,
        uint256 payoutWei
    );

    event OfferPurchased(uint256 indexed offerId, address indexed buyer);
    event OfferCancelled(uint256 indexed offerId);
    event OfferSettled(uint256 indexed offerId, address winner, int256 indexValue1e6, uint256 payoutWei);

    constructor(address consumerAddress) {
        consumer = IIndexConsumer(consumerAddress);
    }

    function createOffer(
        bytes32 indexId,
        bytes32 areaId,
        uint32 yyyymmdd,
        uint256 strike1e6,
        Direction direction,
        uint256 premiumWei
    ) external payable returns (uint256 offerId) {
        if (msg.value == 0) revert InvalidValue();

        offerId = nextOfferId++;
        offers[offerId] = Offer({
            seller: msg.sender,
            buyer: address(0),
            indexId: indexId,
            areaId: areaId,
            yyyymmdd: yyyymmdd,
            strike1e6: strike1e6,
            direction: direction,
            premiumWei: premiumWei,
            payoutWei: msg.value,
            cancelled: false,
            settled: false
        });

        emit OfferCreated(offerId, msg.sender, indexId, areaId, yyyymmdd, strike1e6, direction, premiumWei, msg.value);
    }

    function cancelOffer(uint256 offerId) external {
        Offer storage o = offers[offerId];
        if (o.seller != msg.sender) revert NotSeller();
        if (o.cancelled) revert Cancelled();
        if (o.settled) revert Settled();
        if (o.buyer != address(0)) revert AlreadyPurchased();

        o.cancelled = true;
        emit OfferCancelled(offerId);

        (bool ok,) = o.seller.call{ value: o.payoutWei }("");
        require(ok, "refund failed");
    }

    function buy(uint256 offerId) external payable {
        Offer storage o = offers[offerId];
        if (o.cancelled) revert Cancelled();
        if (o.settled) revert Settled();
        if (o.buyer != address(0)) revert AlreadyPurchased();
        if (msg.value != o.premiumWei) revert InvalidValue();

        o.buyer = msg.sender;
        emit OfferPurchased(offerId, msg.sender);

        (bool ok,) = o.seller.call{ value: o.premiumWei }("");
        require(ok, "premium transfer failed");
    }

    function settle(uint256 offerId) external {
        Offer storage o = offers[offerId];
        if (o.cancelled) revert Cancelled();
        if (o.settled) revert Settled();
        if (o.buyer == address(0)) revert NotAllowed();

        (bytes32 datasetHash, int256 value1e6,, uint64 reportedAt) =
            consumer.commitments(o.indexId, o.areaId, o.yyyymmdd);

        if (reportedAt == 0 || datasetHash == bytes32(0)) revert IndexNotAvailable();
        
        bool buyerWins;
        int256 strike = int256(o.strike1e6);

        if (o.direction == Direction.AboveOrEqual) {
            buyerWins = (value1e6 >= strike);
        } else {
            buyerWins = (value1e6 < strike);
        }


        address winner = buyerWins ? o.buyer : o.seller;
        o.settled = true;

        (bool ok,) = winner.call{ value: o.payoutWei }("");
        require(ok, "payout failed");

        emit OfferSettled(offerId, winner, value1e6, o.payoutWei);
    }
}
