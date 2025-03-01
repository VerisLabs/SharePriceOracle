// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {SharePriceRouter} from "../src/SharePriceRouter.sol";
import {ISharePriceRouter} from "../src/interfaces/ISharePriceRouter.sol";

contract SharePriceRouterTest is Test {
    SharePriceRouter public router;

    function setUp() public {
        router = new SharePriceRouter(
            address(this),
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }

    function test_getLatestPrice_noAdapters() public {
        vm.expectRevert(SharePriceRouter.NoValidPrice.selector);
        router.getLatestPrice(address(0), true);
    }

    function test_getLatestPrice_withAdapter() public {
        MockAdapter adapter = new MockAdapter();
        router.addAdapter(address(adapter), 1);
        adapter.setPrice(100e18);

        (uint256 price, uint64 timestamp) = router.getLatestPrice(address(0), true);
        assertEq(price, 100e18);
        assertEq(timestamp, block.timestamp);
    }

    function test_getLatestPrice_multipleAdapters() public {
        MockAdapter adapter1 = new MockAdapter();
        MockAdapter adapter2 = new MockAdapter();
        router.addAdapter(address(adapter1), 1);
        router.addAdapter(address(adapter2), 2);

        adapter1.setPrice(100e18);
        adapter2.setPrice(200e18);

        (uint256 price, uint64 timestamp) = router.getLatestPrice(address(0), true);
        assertEq(price, 100e18);
        assertEq(timestamp, block.timestamp);
    }

    function test_getLatestPrice_adapterReverts() public {
        MockAdapter adapter = new MockAdapter();
        router.addAdapter(address(adapter), 1);
        adapter.setShouldRevert(true);

        vm.expectRevert(SharePriceRouter.NoValidPrice.selector);
        router.getLatestPrice(address(0), true);
    }

    function test_getLatestPrice_sequencerDown() public {
        MockAdapter adapter = new MockAdapter();
        router.addAdapter(address(adapter), 1);
        adapter.setPrice(100e18);

        MockSequencer sequencer = new MockSequencer();
        router.setSequencer(address(sequencer));
        sequencer.setStatus(true, block.timestamp - 3600);

        vm.expectRevert(SharePriceRouter.SequencerDown.selector);
        router.getLatestPrice(address(0), true);
    }

    function test_getLatestPrice_gracePeriod() public {
        MockAdapter adapter = new MockAdapter();
        router.addAdapter(address(adapter), 1);
        adapter.setPrice(100e18);

        MockSequencer sequencer = new MockSequencer();
        router.setSequencer(address(sequencer));
        sequencer.setStatus(false, block.timestamp - router.GRACE_PERIOD_TIME() - 1);

        vm.expectRevert(SharePriceRouter.GracePeriodNotOver.selector);
        router.getLatestPrice(address(0), true);
    }

    function test_getLatestSharePrice() public {
        MockAdapter adapter = new MockAdapter();
        router.addAdapter(address(adapter), 1);
        adapter.setPrice(100e18);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(router.chainId(), address(0), address(0));
        assertEq(price, 100e18);
        assertEq(timestamp, block.timestamp);
    }

    function test_calculateSharePrice() public {
        MockAdapter adapter = new MockAdapter();
        router.addAdapter(address(adapter), 1);
        adapter.setPrice(100e18);

        (uint256 price, uint64 timestamp) = router.calculateSharePrice(address(0), address(0));
        assertEq(price, 100e18);
        assertEq(timestamp, block.timestamp);
    }

    function test_updateSharePrices() public {
        ISharePriceRouter.VaultReport[] memory reports = new ISharePriceRouter.VaultReport[](1);
        reports[0] = ISharePriceRouter.VaultReport({
            vaultAddress: address(0),
            sharePrice: 100e18,
            lastUpdate: uint64(block.timestamp),
            chainId: 1,
            rewardsDelegate: address(0),
            asset: address(0),
            assetDecimals: 18
        });

        router.updateSharePrices(1, reports);

        ISharePriceRouter.VaultReport memory report = router.getLatestSharePriceReport(1, address(0));
        assertEq(report.sharePrice, 100e18);
        assertEq(report.lastUpdate, block.timestamp);
    }

    function test_notifyFeedRemoval() public {
        MockAdapter adapter = new MockAdapter();
        router.addAdapter(address(adapter), 1);

        vm.prank(address(adapter));
        router.notifyFeedRemoval(address(0));
        
        assertEq(router.adapterPriorities(address(adapter)), 0);
    }
}

contract MockAdapter {
    uint256 public price;
    bool public shouldRevert;

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function getPrice(address, bool) external view returns (uint256, uint256, bool) {
        require(!shouldRevert, "MockAdapter: reverted");
        return (price, block.timestamp, true);
    }

    function isSupportedAsset(address) external pure returns (bool) {
        return true;
    }
}

contract MockSequencer {
    bool public isDown;
    uint256 public startedAt;

    function setStatus(bool _isDown, uint256 _startedAt) external {
        isDown = _isDown;
        startedAt = _startedAt;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, isDown ? 1 : 0, startedAt, 0, 0);
    }
} 