// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library Constants {
    // Chain IDs
    uint32 constant BASE = 8453;
    uint32 constant OPTIMISM = 10;
    uint32 constant ARBITRUM = 42161;
    uint32 constant POLYGON = 137;

    // Asset Configuration
    struct AssetConfig {
        address token;
        address adapter;
        address priceFeed;
        uint8 priority;
        uint256 heartbeat;
        bool inUSD;
    }

    // Chain Configuration
    struct ChainConfig {
        uint32 chainId;
        uint32 lzEndpointId;
        address lzEndpoint;
        address ethUsdFeed;
        mapping(address => address) crossChainMap;
    }

    // Get Base chain assets
    function getBaseAssets() internal pure returns (AssetConfig[] memory) {
        AssetConfig[] memory assets = new AssetConfig[](6);

        // Stablecoins
        assets[0] = AssetConfig({
            token: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC
            priceFeed: 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B,
            priority: 0,
            heartbeat: 86400,
            inUSD: true,
            adapter: 0xA6779d614d351fC52ae6D8558Ecd651763Af33DE
        });

        assets[1] = AssetConfig({
            token: 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2, // USDT
            priceFeed: 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9,
            priority: 0,
            heartbeat: 86400,
            inUSD: true,
            adapter: 0xA6779d614d351fC52ae6D8558Ecd651763Af33DE
        });

        // ETH assets
        assets[2] = AssetConfig({
            token: 0x4200000000000000000000000000000000000006, // WETH
            priceFeed: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70,
            priority: 0,
            heartbeat: 1200,
            inUSD: true,
            adapter: 0xA6779d614d351fC52ae6D8558Ecd651763Af33DE
        });

        assets[3] = AssetConfig({
            token: 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452, // stETH
            priceFeed: 0xf586d0728a47229e747d824a939000Cf21dEF5A0,
            priority: 0,
            heartbeat: 86400,
            inUSD: false,
            adapter: 0xA6779d614d351fC52ae6D8558Ecd651763Af33DE
        });

        // BTC assets
        assets[4] = AssetConfig({
            token: 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c, // WBTC
            priceFeed: 0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E,
            priority: 0,
            heartbeat: 1200,
            inUSD: true,
            adapter: 0xA6779d614d351fC52ae6D8558Ecd651763Af33DE
        });

        assets[5] = AssetConfig({
            token: 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf, // tBTC
            priceFeed: 0x6D75BFB5A5885f841b132198C9f0bE8c872057BF,
            priority: 0,
            heartbeat: 86400,
            inUSD: true,
            adapter: 0xA6779d614d351fC52ae6D8558Ecd651763Af33DE
        });

        return assets;
    }

    // Get Optimism assets
    function getOptimismAssets() internal pure returns (address[] memory) {
        address[] memory assets = new address[](7);
        // Both USDC and USDCe on Optimism map to USDC on Base
        assets[0] = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC
        assets[1] = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58; // USDT
        assets[2] = 0x4200000000000000000000000000000000000006; // WETH
        assets[3] = 0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb; // stETH
        assets[4] = 0x68f180fcCe6836688e9084f035309E29Bf0A2095; // WBTC
        assets[5] = 0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40; // tBTC
        assets[6] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607; // USDCe (also maps to Base USDC)
        return assets;
    }

    // Get Arbitrum assets
    function getArbitrumAssets() internal pure returns (address[] memory) {
        address[] memory assets = new address[](6);
        assets[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        assets[1] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        assets[2] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        assets[3] = 0x5979D7b546E38E414F7E9822514be443A4800529; // stETH
        assets[4] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        assets[5] = 0x7E2a1eDeE171C5B19E6c54D73752396C0A572594; // tBTC
        return assets;
    }

    function getChainConfig(
        uint32 chainId
    )
        internal
        pure
        returns (uint32 lzEndpointId, address lzEndpoint, address ethUsdFeed)
    {
        if (chainId == BASE) {
            return (
                30_184,
                0x1a44076050125825900e736c501f859c50fE728c,
                0xfE1587A048b283ecEDe0AF9cbDfd6a0e531B732B
            );
        } else if (chainId == OPTIMISM) {
            return (
                30_111,
                0x1a44076050125825900e736c501f859c50fE728c,
                0x052f1ba9cDC9859Fd19849484b69000E54AabBA6
            );
        } else if (chainId == ARBITRUM) {
            return (
                30_110,
                0x1a44076050125825900e736c501f859c50fE728c,
                0xE304C2CD95eADA80C61e9782c3089fCc1576d585
            );
        }

        revert("Unsupported chain");
    }
}
