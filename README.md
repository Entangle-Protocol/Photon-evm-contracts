<div align="center">
  <a href="https://entangle.fi/">
    <img src="https://docs.entangle.fi/~gitbook/image?url=https%3A%2F%2F4040807501-files.gitbook.io%2F%7E%2Ffiles%2Fv0%2Fb%2Fgitbook-x-prod.appspot.com%2Fo%2Fspaces%252F5AajewgFWO9EkufRORqL%252Fuploads%252FDfRGGJJASR0PFitX6rbx%252FTwitter%2520%281%29.png%3Falt%3Dmedia%26token%3D09e49fe6-1b92-4bed-82e6-730ba785afaf&width=1248&dpr=2&quality=100&sign=5fbbb9f4&sv=1" alt="Entangle" style="width:100%;"/>
  </a>

  <h1>Photon</h1>

  <p>
    <strong>Cross-chain messaging protocol</strong>
  </p>

  <p>
    <a href="https://docs.entangle.fi/entangle-components/photon-messaging"><img alt="Docs" src="https://img.shields.io/badge/Readthedocs-%23000000.svg?style=for-the-badge&logo=readthedocs&logoColor=white)"/></a>
  </p>
</div>

Photon Messaging is an omnichain protocol that facilitates secure and efficient cross-chain communication for both EVM and non-EVM blockchains. It enables developers to send customized messages across diverse blockchain networks, supporting seamless asset transfers and operations.

## Table of Contents

- [Build and install](#build-and-install)
    - [Components](#components)
    - [Compiling project contracts](#building-the-project)
    - [Deployments](#protocol-contracts--deployments)
    - [Photon integration](#integrate)
- [Testing](#testing)
    - [Local tests](#local-testing)
    - [Testnet and mainnet testing](#testnet--mainnet-testing)
- [Audits](#audits)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [License](LICENSE)

## Build and Install

### Building the project 

To compile the project contracts use:
```bash
yarn && yarn build
```

### Components

- Operational flow of sending decentralized blockchain operations goes through an intricate network of smart contracts such as [Endpoint system](https://docs.entangle.fi/entangle-components/photon-messaging/end-points-system)
- Photon [Agent network](https://docs.entangle.fi/entangle-components/photon-messaging/entangle-agent-network) is a Delegated Proof of Stake (DPoS) distributed architecture with off-chain machines
- [Photon Executors](https://docs.entangle.fi/entangle-components/photon-messaging/executors) are backend programs tasked with retrieving and executing approved operations from various blockchains
- [Photon Data Streamer](https://docs.entangle.fi/entangle-components/photon-messaging/photon-data-streamer) is part of the Photon infrastructure, optimized for real-time data transmission to enable immediate processing and analysis
- [Universal Data Feeds](https://docs.entangle.fi/entangle-components/universal-data-feeds) is part of the Photon infrastructure created for collection, processing and distributing data of any format between different blockchains. See UDF repositories [here](https://github.com/Entangle-Protocol?q=udf&type=all&language=&sort=)


### Protocol Contracts & Deployments

Photon contract deployments (both testnet & mainnet), contracts themselves and script utilies for integration can be found in [SDK](https://www.npmjs.com/package/@entangle_protocol/oracle-sdk). Install it with:
```bash
yarn add "@entangle_protocol/oracle-sdk"
```


Refer to the Photon Messaging [Docs](https://docs.entangle.fi/entangle-components/photon-messaging) for building and integrating into Photon

### Integrate

If you want to build on Photon or to be a part of any protocol, refer to our integration guides:

- [Photon](https://docs.entangle.fi/photon-guides/how-to-integrate) Integration 
- [UDF](https://docs.entangle.fi/universal-data-feeds-guides/how-to-integrate) Integration
- How to [become an Agent](https://docs.entangle.fi/entangle-components/photon-messaging/entangle-agent-network/how-to-become-an-agent)

## Testing

### Local testing

To test Photon, some dependecies should be installed. Run:
```bash
yarn && yarn build && yarn test
```

for both installation and testing. Or just:
```bash
yarn test
```
in case you've already run build commands.

### Testnet & mainnet testing

For testing on testnet or mainnet see [deployments](#protocol-contracts--deployments) and use these contract addresses for cross-chain communication of your protocol. 

If you want to test your project with one of protocols already connected to **_Photon_** or build on top of it - please refer to documentation of this particular protocol.


## Audits

Audits related to **_Photon_**:

- Halborn [audit](https://www.halborn.com/audits/entangle-labs/photon-messaging-protocol-evm)
- Sentnl [audit](https://docs.entangle.fi/audits/audits-by-sentnl)
- Astrarizon [audit](https://docs.entangle.fi/audits/audits-by-astrarizon)

## License 
This project is licensed under the [MIT License](LICENSE) (License was changed from BSL 1.1)