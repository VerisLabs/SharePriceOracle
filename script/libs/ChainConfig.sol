// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library ChainConfig {
    struct Config {
        uint32 chainId;
        uint32 lzEndpointId;
        address ethUsdFeed;
        address lzEndpoint;
        string name;
    }

    error UnsupportedChain(uint256 chainId);

    function getConfig(uint256 chainId) internal pure returns (Config memory) {
        // Mainnet L2s
        if (chainId == 8453) { // Base
            return Config({
                chainId: 8453,
                lzEndpointId: 184,
                ethUsdFeed: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70,
                lzEndpoint: 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7,
                name: "Base"
            });
        } else if (chainId == 10) { // Optimism
            return Config({
                chainId: 10,
                lzEndpointId: 111,
                ethUsdFeed: 0x13e3Ee699D1909E989722E753853AE30b17e08c5,
                lzEndpoint: 0x3c2269811836af69497E5F486A85D7316753cf62,
                name: "Optimism"
            });
        } else if (chainId == 42161) { // Arbitrum
            return Config({
                chainId: 42161,
                lzEndpointId: 110,
                ethUsdFeed: 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,
                lzEndpoint: 0x3c2269811836af69497E5F486A85D7316753cf62,
                name: "Arbitrum"
            });
        }

        // Testnets
        else if (chainId == 84531) { // Base Goerli
            return Config({
                chainId: 84531,
                lzEndpointId: 184,
                ethUsdFeed: 0xcD2A119bD1F7DF95d706DE6F2057fDD45A0503E2,
                lzEndpoint: 0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab,
                name: "Base Goerli"
            });
        } else if (chainId == 420) { // Optimism Goerli
            return Config({
                chainId: 420,
                lzEndpointId: 111,
                ethUsdFeed: 0x57241A37733983F97C4Ab06448F244A1E0Ca0ba8,
                lzEndpoint: 0xA14DBac33f5b5a2EDF459196E4EA42a680ABfeB5,
                name: "Optimism Goerli"
            });
        } else if (chainId == 421613) { // Arbitrum Goerli
            return Config({
                chainId: 421613,
                lzEndpointId: 110,
                ethUsdFeed: 0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08,
                lzEndpoint: 0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab,
                name: "Arbitrum Goerli"
            });
        }

        revert UnsupportedChain(chainId);
    }
}
