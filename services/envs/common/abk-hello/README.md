# Serverless - ABK Python Template
This project created to easily create new services using [Serverless framework](https://www.serverless.com/).
For detailed instructions, please refer to the [documentation](https://www.serverless.com/framework/docs/providers/aws/).

## Installation/deployment instructions
To create new service, please execute shell script in the service directory: `./createNewService.sh py <name-of-your-new-service> <env>`

**Requirements**: Python `(v 3.11.x)`. If you're using [uv](https://github.com/astral-sh/uv), [uv-docs](https://docs.astral.sh/uv/guides/tools/)
- to install uv run: `brew install uv` on MacOS or `sudo apt install uv` on Linux.
- `uv sync` - will download all dependencies
- `source .venv/bin/activate` - activate virtual env
- `direnv allow` - will allow to load uv initialization from .envrc
- `uv add <dependency>` - to add dependency
- `uv remove <dependency>` - to remove dependency


### Using make rules
| dependency installations   | description                                                           |
| :------------------------- | :-------------------------------------------------------------------- |
| `make install`             | install project dependencies                                          |
| `make install_dev`         | install project dependencies and dependencies required for unit tests |
| `make install_debug`       | install project dependencies, unit tests and debug dependencies       |
| `make export_requirements` | export uv dependencies to requirements files                          |

| domain commands      | description                                                           |
| :------------------- | :-------------------------------------------------------------------- |
| `make create_domain` | creates custom domain for the service in currently active environment |
| `make delete_domain` | deletes custom domain for the service in currently active environment |

| deployment commands | description                                            |
| :------------------ | :----------------------------------------------------- |
| `make deploy`       | deploys service to currently active environment        |
| `make deploy_env`   | deploys service to environment, which is set in .envrc |
| `make deploy_dev`   | deploys service to dev environment                     |
| `make deploy_qa`    | deploys service to qa environment                      |
| `make deploy_prod`  | deploys service to prod environment                    |

| remove commands    | description                                              |
| :----------------- | :------------------------------------------------------- |
| `make remove`      | removes service from currently active environment        |
| `make remove_env`  | removes service from environment, which is set in .envrc |
| `make remove_dev`  | removes service from dev environment                     |
| `make remove_qa`   | removes service from qa environment                      |
| `make remove_prod` | removes service from prod environment                    |

| unit tests commands | description                                                     |
| :------------------ | :-------------------------------------------------------------- |
| `make test`         | runs unit tests                                                 |
| `make test_v`       | runs unit tests verbosely                                       |
| `make test_ff`      | runs unit tests fast fail, 1st test failing will stop the tests |
| `make test_vff`     | runs unit tests verbosely and with fast fail option             |
| `make coverage`     | runs unit tests with test coverage                              |

| other commands  | description                                                   |
| :-------------- | :------------------------------------------------------------ |
| `make clean`    | cleans project from all python and serverless build artifacts |
| `make settings` | displays some settings                                        |
| `make help`     | displays help page with make rules options                    |


### Remotely
Copy and replace your `url` - found in Serverless `deploy` command output - and `name` parameter in the following `curl` command in your terminal, Postman or vscode extension: `Postman` to test your newly deployed application. Don't forget to use authentication token.

### Project structure

```
.
├── src                                 # directory with production code sources
│   └── abk_hello
│       ├── __init__.py                 # module init
│       ├── abk_hello_io.py             # example lambda IO (Lambda Request and Response definitions)
│       └── abk_hello.py                # example lambda code
├── tests                               # unit tests directory
│   └── test_abk_hello.py               # unit tests for example lambda
├── Makefile                             # Makefile, which creates project rules
├── package-lock.json
├── package.json                        # some serverless plugin dependencies
├── publish.sh                          # shell script to deploy service
├── pyproject.toml                      # uv python project file
├── README.md                           # This file
├── requirements_debug.txt              # all python dependencies for debug
├── requirements_dev.txt                # project dependencies for unit tests
├── requirements.txt                    # project python dependencies
├── serverless.yml                      # serverless config
└── uv.lock                             #
```
