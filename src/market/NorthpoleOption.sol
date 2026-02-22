// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IIndexConsumer} from "../interfaces/IIndexConsumer.sol";

contract NorthpoleOption {
    enum Direction {
        AboveOrEqual,
        Below
    }

    // immutable “instrument definition”
    IIndexConsumer public immutable consumer;
    address public immutable seller;

    bytes32 public immutable indexId;
    bytes32 public immutable areaId;
    uint32 public immutable yyyymmdd;
    int256 public immutable strike1e6;
    Direction public immutable direction;

    uint256 public immutable premiumWei;
    uint256 public immutable payoutWei;
    uint64 public immutable buyDeadline; // unix seconds (UTC)

    // lifecycle
    address public buyer;
    bool public cancelled;
    bool public settled;

    error AlreadyPurchased();
    error Cancelled();
    error AlreadySettled();
    error NotSeller();
    error InvalidValue();
    error NotAllowed();
    error BuyClosed();
    error IndexNotAvailable();
    error IndexAlreadyPublished();

    event Purchased(address indexed buyer);
    event CancelledBySeller();
    event Settled(address indexed winner, int256 indexValue1e6, bytes32 datasetHash, uint256 payoutWei);

    constructor(
        address consumerAddress,
        address seller_,
        bytes32 indexId_,
        bytes32 areaId_,
        uint32 yyyymmdd_,
        int256 strike1e6_,
        Direction direction_,
        uint256 premiumWei_,
        uint64 buyDeadline_
    ) payable {
        if (msg.value == 0) revert InvalidValue();
        if (buyDeadline_ <= block.timestamp) revert BuyClosed();

        consumer = IIndexConsumer(consumerAddress);
        seller = seller_;

        indexId = indexId_;
        areaId = areaId_;
        yyyymmdd = yyyymmdd_;
        strike1e6 = strike1e6_;
        direction = direction_;

        premiumWei = premiumWei_;
        payoutWei = msg.value;
        buyDeadline = buyDeadline_;

        // Don’t allow creation if index already published.
        (,,, uint64 reportedAt) = consumer.commitments(indexId_, areaId_, yyyymmdd_);
        if (reportedAt != 0) revert IndexAlreadyPublished();
    }

    function cancel() external {
        if (msg.sender != seller) revert NotSeller();
        if (cancelled) revert Cancelled();
        if (settled) revert AlreadySettled();
        if (buyer != address(0)) revert AlreadyPurchased();

        cancelled = true;
        emit CancelledBySeller();

        (bool ok,) = seller.call{value: payoutWei}("");
        require(ok, "refund failed");
    }

    function buy() external payable {
        if (cancelled) revert Cancelled();
        if (settled) revert AlreadySettled();
        if (buyer != address(0)) revert AlreadyPurchased();
        if (msg.value != premiumWei) revert InvalidValue();
        if (block.timestamp >= buyDeadline) revert BuyClosed();

        // extra safety: don’t allow buys after index published
        (,,, uint64 reportedAt) = consumer.commitments(indexId, areaId, yyyymmdd);
        if (reportedAt != 0) revert IndexAlreadyPublished();

        buyer = msg.sender;
        emit Purchased(msg.sender);

        (bool ok,) = seller.call{value: premiumWei}("");
        require(ok, "premium transfer failed");
    }

    function settle() external {
        if (cancelled) revert Cancelled();
        if (settled) revert AlreadySettled();
        if (buyer == address(0)) revert NotAllowed();

        (bytes32 datasetHash, int256 value1e6,, uint64 reportedAt) = consumer.commitments(indexId, areaId, yyyymmdd);

        if (reportedAt == 0 || datasetHash == bytes32(0)) revert IndexNotAvailable();

        bool buyerWins = (direction == Direction.AboveOrEqual) ? (value1e6 >= strike1e6) : (value1e6 < strike1e6);

        address winner = buyerWins ? buyer : seller;
        settled = true;

        (bool ok,) = winner.call{value: payoutWei}("");
        require(ok, "payout failed");

        emit Settled(winner, value1e6, datasetHash, payoutWei);
    }
}
