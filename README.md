<div align="center">
  <a href="https://entangle.fi/">
    <img alt="Entangle" style="width: 20%" src=""/>
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

## Components & Docs

- Operational flow of sending decentralized blockchain operations goes through an intricate network of smart contracts such as [Endpoint system](https://docs.entangle.fi/entangle-components/photon-messaging/end-points-system).
- Photon [Agent network](https://docs.entangle.fi/entangle-components/photon-messaging/entangle-agent-network) is a Delegated Proof of Stake (DPoS) distributed architecture with off-chain machines.
- [Photon Executors](https://docs.entangle.fi/entangle-components/photon-messaging/executors) backend programs tasked with retrieving and executing approved operations from various blockchains.
- [Photon Data Streamer](https://docs.entangle.fi/entangle-components/photon-messaging/photon-data-streamer) is part of the Photon infrastructure, optimized for real-time data transmission to enable immediate processing and analysis
- [Universal Data Feeds](https://docs.entangle.fi/entangle-components/universal-data-feeds) is part of the Photon infrastructure created for collection, processing and disributing data of any format between different blockchains.

Refer to the Photon Messaging [Docs](https://docs.entangle.fi/entangle-components/photon-messaging) for building and integrating into Photon.

## Build & Test
```bash
yarn && yarn build && yarn test
```

## Protocol Contracts & Deployments

Photon contracts, contract deployments and utilies for integration can be found in [SDK](https://www.npmjs.com/package/@entangle_protocol/oracle-sdk). Install it with:
```bash
yarn add "@entangle_protocol/oracle-sdk"
```

## Build & Integrate

If you want to build on Photon or to be a part of protocol, refer to our integration guides:

- [Photon](https://docs.entangle.fi/photon-guides/how-to-integrate) Integration 
- [UDF](https://docs.entangle.fi/universal-data-feeds-guides/how-to-integrate) Integration
- How to [become an Agent](https://docs.entangle.fi/entangle-components/photon-messaging/entangle-agent-network/how-to-become-an-agent)

## Audits
- Halborn [audit](https://docs.entangle.fi/audits/audits-by-halborn)
- Sentnl [audit](https://docs.entangle.fi/audits/audits-by-sentnl)
- Astrarizon [audit](https://docs.entangle.fi/audits/audits-by-astrarizon)

## License 
Photon protocol is licensed under [BSL 1.1 License](LICENSE)