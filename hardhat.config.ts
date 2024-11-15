import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";

import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ganache";
import "@openzeppelin/hardhat-upgrades";
import "solidity-docgen";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import "@matterlabs/hardhat-zksync";
import "./scripts/tasks";
import "@matterlabs/hardhat-zksync-solc";

dotenv.config();

import { MochaOptions } from "mocha";
export const projectRoot = __dirname;

// BigInt doesn't serialize to string as default, see
// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/BigInt#use_within_json
BigInt.prototype.toJSON = function () {
    return this.toString();
};

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: "0.8.19",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 0,
                    },
                    viaIR: true,
                },
            },
            {
                version: "0.8.20",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 0,
                    },
                    viaIR: true,
                },
            },
            {
                version: "0.8.22",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 0,
                    },
                    viaIR: true,
                },
            },
        ],
    },
    zksolc: {
        version: "latest", // optional.
        settings: {
          enableEraVMExtensions: false, // optional.  Enables Yul instructions available only for ZKsync system contracts and libraries
          forceEVMLA: false, // optional. Falls back to EVM legacy assembly if there is a bug with Yul
          optimizer: {
            enabled: true, // optional. True by default
            mode: '3', // optional. 3 by default, z to optimize bytecode size
            fallback_to_optimizing_for_size: false, // optional. Try to recompile with optimizer mode "z" if the bytecode is too large
          },
          suppressedWarnings: ['txorigin', 'sendtransfer'], // Suppress specified warnings. Currently supported: txorigin, sendtransfer
          suppressedErrors: ['txorigin', 'sendtransfer'], // Suppress specified errors. Currently supported: txorigin, sendtransfer
        }
    },
    networks: {
        hardhat: {
            disabled: true,
            chainId: 33133,
            accounts: {
                count: 1000,
            },
            allowUnlimitedContractSize: true,
            blockGasLimit: 110000000,
            gas: "auto",
        },
        entangle: {
            chainId: 33033,
            url: process.env.MAINNET_ENTANGLE_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
        },
        ethereum: {
            chainId: 1,
            url: process.env.MAINNET_ETH_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
        },
        shasta: {
            chainId: 2494104990,
            url: process.env.MAINNET_ETH_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
        },
        tron: {
            chainId: 728126428,
            url: process.env.MAINNET_ETH_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
        },
        mantle: {
            chainId: 5000,
            url: process.env.MAINNET_MANTLE_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
        },
        binance: {
            chainId: 56,
            url: process.env.MAINNET_BINANCE_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || ""
            }
        },
        base: {
            chainId: 8453,
            url: process.env.MAINNET_BASE_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || ""
            }
        },
        arbitrum: {
            chainId: 42161,
            url: process.env.MAINNET_ARBITRUM_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || ""
            }
        },
        optimism: {
            chainId: 10,
            url: process.env.MAINNET_OPTIMISM_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || ""
            }
        },
        avalanche: {
            chainId: 43114,
            url: process.env.MAINNET_AVAX_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || ""
            }
        },
        polygon: {
            chainId: 137,
            url: process.env.POLYGON_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || ""
            }
        },
        blast: {
            chainId: 81457,
            url: process.env.MAINNET_BLAST_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || ""
            }
        },
        linea: {
            chainId: 59144,
            url: process.env.MAINNET_LINEA_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || ""
            }
        },
        core: {
            chainId: 1116,
            url: process.env.MAINNET_CORE_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || ""
            }
        },
        tent: {
            chainId: 33133,
            url: process.env.ENT_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
            timeout: 100000000,
        },
        eth_sepolia: {
            chainId: 11155111,
            url: process.env.ETH_SEPOLIA_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            }
        },
        arb_sepolia: {
            chainId: 421614,
            url: process.env.ARB_SEPOLIA_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            }
        },
        mantle_sepolia: {
            chainId: 5003,
            url: process.env.MANTLE_SEPOLIA_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            }
        },
        zksync: {
            chainId: 324,
            url: process.env.ZKSYNC_URL || "",
            accounts: {
                mnemonic: process.env.MNEMONIC || "",
            },
            zksync: true,
            ethNetwork: "mainnet",
        }
    },
    etherscan: {
        apiKey: process.env.BSCSCAN_KEY,
    },
    mocha: {
        timeout: 100000000,
        reporter: process.env.CI && "xunit",
        reporterOptions: process.env.CI && {
            output: "out.xml",
        },
    } as MochaOptions,
    gasReporter: {
        enabled: true,
        noColors: true,
        currency: "USD",
        gasPriceApi:
            "https://api.etherscan.io/api?module=proxy&action=eth_gasPrice",
        coinmarketcap: process.env.CMC,
        token: "ETH",
    },
    docgen: {
        exclude: ["test", "stream_data/test"],
        pages: "files",
        outputDir: "docs/contracts",
    },
};

export default config;
