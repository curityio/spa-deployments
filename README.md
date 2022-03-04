# SPA Deployments

[![Quality](https://img.shields.io/badge/quality-demo-red)](https://curity.io/resources/code-examples/status/)
[![Availability](https://img.shields.io/badge/availability-source-blue)](https://curity.io/resources/code-examples/status/)

Supporting resources for deployment of SPA code examples which use the [Token Handler Pattern](https://curity.io/resources/learn/the-token-handler-pattern/).\
The token handler manages OAuth work for the SPA and issues secure cookies to use in the browser:

![Logical Components](/images/logical-components.png)

## Deployment Overview

The token handler pattern requires additional supporting components to be deployed:

![Deployed Components](/images/deployed-components.png)

## Deployment Steps

Deployment on development computer involves the following main steps:

| Step | Description |
| ---- | ----------- |
| Prerequisites | Ensuring that the correct prerequisite tools are installed |
| Build Code | Building code and dependencies into Docker images |
| Configure SSL Trust | Ensuring that development certificates are trusted by the system |
| Deploy the System | Deploying the Curity Identity Server and other supporting components |
| Run the SPA | Browsing to the SPA and signing in as the preconfigured user account |

## Running an End-to-End Flow

Start with the main SPA repository, and follow the instructions in these pages:

- [Standard SPA using an Authorization Code Flow (PKCE) and a Client Secret](https://github.com/curityio/web-oauth-via-bff/doc/Standard.md)
- [Financial-grade SPA using Mutual TLS, PAR and JARM](https://github.com/curityio/web-oauth-via-bff/doc/Financial.md)

## Running a Token Handler without a Browser

See the following repositories for further details on how to extend a token handler:

- [Standard Token Handler in Node.js](https://github.com/curityio/token-handler-node-express)
- [Financial-grade Token Handler in Kotlin](https://github.com/curityio/token-handler-kotlin-spring-fapi)

## More Information

Please visit [curity.io](https://curity.io/) for more information about the Curity Identity Server.
