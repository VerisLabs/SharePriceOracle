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
    error UnsupportedEndpoint(uint32 lzEndpointId);

    function getConfigByLzId(
        uint32 lzEndpointId
    ) internal pure returns (Config memory) {
        if (lzEndpointId == 30110) {
            return getConfig(42161); // Arbitrum
        } else if (lzEndpointId == 30106) {
            return getConfig(43114); // Avalanche
        } else if (lzEndpointId == 30184) {
            return getConfig(8453); // Base
        } else if (lzEndpointId == 30102) {
            return getConfig(56); // BNB
        } else if (lzEndpointId == 30101) {
            return getConfig(1); // Ethereum
        } else if (lzEndpointId == 30112) {
            return getConfig(250); // Fantom
        } else if (lzEndpointId == 30183) {
            return getConfig(59144); // Linea
        } else if (lzEndpointId == 30111) {
            return getConfig(10); // Optimism
        } else if (lzEndpointId == 30109) {
            return getConfig(137); // Polygon
        }
        /*
        else if (lzEndpointId == 30243) {
            return getConfig(81457); // Blast
        } else if (lzEndpointId == 40245) {
            return getConfig(84532); // Base Sepolia
        } else if (lzEndpointId == 40232) {
            return getConfig(11155420); // Optimism Sepolia
        } else if (lzEndpointId == 40231) {
            return getConfig(421614); // Arbitrum Sepolia
        }
        */
        revert UnsupportedEndpoint(lzEndpointId);
    }

    function getConfig(uint256 chainId) internal pure returns (Config memory) {
        if (chainId == 42161) {
            // Arbitrum
            return
                Config({
                    chainId: 42161,
                    lzEndpointId: 30110,
                    ethUsdFeed: 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "Arbitrum"
                });
        } else if (chainId == 43114) {
            // Avalanche
            return
                Config({
                    chainId: 43114,
                    lzEndpointId: 30106,
                    ethUsdFeed: 0x976B3D034E162d8bD72D6b9C989d545b839003b0,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "Avalanche"
                });
        } else if (chainId == 8453) {
            // Base
            return
                Config({
                    chainId: 8453,
                    lzEndpointId: 30184,
                    ethUsdFeed: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "Base"
                });
        } else if (chainId == 56) {
            // BNB
            return
                Config({
                    chainId: 56,
                    lzEndpointId: 30102,
                    ethUsdFeed: 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "BNB"
                });
        } else if (chainId == 1) {
            // Ethereum
            return
                Config({
                    chainId: 1,
                    lzEndpointId: 30101,
                    ethUsdFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "Ethereum"
                });
        } else if (chainId == 250) {
            // Fantom
            return
                Config({
                    chainId: 250,
                    lzEndpointId: 30112,
                    ethUsdFeed: 0x11DdD3d147E5b83D01cee7070027092397d63658,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "Fantom"
                });
        } else if (chainId == 59144) {
            // Linea
            return
                Config({
                    chainId: 59144,
                    lzEndpointId: 30183,
                    ethUsdFeed: 0x3c6Cd9Cc7c7a4c2Cf5a82734CD249D7D593354dA,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "Linea"
                });
        } else if (chainId == 10) {
            // Optimism
            return
                Config({
                    chainId: 10,
                    lzEndpointId: 30111,
                    ethUsdFeed: 0x13e3Ee699D1909E989722E753853AE30b17e08c5,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "Optimism"
                });
        } else if (chainId == 137) {
            // Polygon
            return
                Config({
                    chainId: 137,
                    lzEndpointId: 30109,
                    ethUsdFeed: 0xF9680D99D6C9589e2a93a78A04A279e509205945,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "Polygon"
                });
        }
        /*
        else if (chainId == 81457) {
            // Blast
            return
                Config({
                    chainId: 81457,
                    lzEndpointId: 30243,
                    ethUsdFeed: ,
                    lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                    name: "Blast"
                });
        } 
        // Testnets
        else if (chainId == 84532) {
            // Base Sepolia
            return
                Config({
                    chainId: 84532,
                    lzEndpointId: 40245,
                    ethUsdFeed: ,
                    lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
                    name: "Base Sepolia"
                });
        } else if (chainId == 11155420) {
            // Optimism Sepolia 
            return
                Config({
                    chainId: 11155420,
                    lzEndpointId: 40232,
                    ethUsdFeed: ,
                    lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
                    name: "Optimism Sepolia"
                });
        } else if (chainId == 421614) {
            // Arbitrum Goerli
            return
                Config({
                    chainId: 421614,
                    lzEndpointId: 40231,
                    ethUsdFeed: ,
                    lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
                    name: "Arbitrum Sepolia"
                });
        }
        */
        revert UnsupportedChain(chainId);
    }
}
