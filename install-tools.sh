#!/bin/bash

EXPECTED_NUMBER_OF_PARAMS=0
COMMON_LIB_FILE="./common-lib.sh"
EXIT_CODE=0

# -----------------------------------------------------------------------------
# functions
# -----------------------------------------------------------------------------
InstallRequiredToolsUsingBrew() {
    LCL_TOOL=(
        aws
        jq
        parallel
        # serverless
        terraform
        yq
    )
    LCL_PACKAGE=(
        awscli
        jq
        parallel
        # serverless
        terraform
        yq
    )

    echo
    PrintTrace "$TRACE_FUNCTION" "----------------------------------------------------------------------"
    PrintTrace "$TRACE_FUNCTION" "| ${FUNCNAME[0]} ()"
    PrintTrace "$TRACE_FUNCTION" "----------------------------------------------------------------------"

    for (( i = 0; i < ${#LCL_TOOL[@]}; i++)); do
        PrintTrace "$$TRACE_INFO"  "\n------------------------\n${LCL_TOOL[$i]} - INSTALL AND CHECK\n------------------------"
        if command -v "${LCL_TOOL[$i]}" >/dev/null 2>&1; then
            which "${LCL_TOOL[$i]}"
        else
            brew install "${LCL_PACKAGE[$i]}"
        fi
        PrintTrace "$$TRACE_INFO"  "\n------------------------\n${LCL_TOOL[$i]} - VERSION\n------------------------"
        ${LCL_TOOL[$i]} --version || exit $?
        PrintTrace "$$TRACE_INFO"  "${YLW}----------------------------------------------------------------------${NC}"
        echo
    done
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
}


InstallRequiredToolsUsingApt() {
    LCL_TOOL=(
        aws
        jq
        parallel
        terraform
        yq
    )
    LCL_PACKAGE=(
        awscli
        jq
        parallel
        terraform
        yq
    )

    echo
    PrintTrace "$TRACE_FUNCTION" "----------------------------------------------------------------------"
    PrintTrace "$TRACE_FUNCTION" "| ${FUNCNAME[0]} ()"
    PrintTrace "$TRACE_FUNCTION" "----------------------------------------------------------------------"

    for (( i = 0; i < ${#LCL_TOOL[@]}; i++)); do
        PrintTrace "$$TRACE_INFO"  "\n------------------------\n${LCL_TOOL[$i]} - INSTALL AND CHECK\n------------------------"
        if command -v "${LCL_TOOL[$i]}" >/dev/null 2>&1; then
            which "${LCL_TOOL[$i]}"
        else
            sudo apt install -y "${LCL_PACKAGE[$i]}"
        fi
        PrintTrace "$$TRACE_INFO"  "\n------------------------\n${LCL_TOOL[$i]} - VERSION\n------------------------"
        ${LCL_TOOL[$i]} --version || exit $?
        PrintTrace "$$TRACE_INFO"  "${YLW}----------------------------------------------------------------------${NC}"
        echo
    done
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
}


InstallRequiredToolsUsingNpm() {
    local LCL_TOOL=(
                    serverless
                )
    local LCL_PACKAGE=(
                    serverless
                  )
    echo
    PrintTrace "$TRACE_FUNCTION" "----------------------------------------------------------------------"
    PrintTrace "$TRACE_FUNCTION" "| ${FUNCNAME[0]} ()"
    PrintTrace "$TRACE_FUNCTION" "----------------------------------------------------------------------"

    for (( i = 0; i < ${#LCL_TOOL[@]}; i++)); do
        PrintTrace "$$TRACE_INFO"  "\n------------------------\n${LCL_TOOL[$i]} - INSTALL AND CHECK\n------------------------"
        if command -v "${LCL_TOOL[$i]}" >/dev/null 2>&1; then
            which "${LCL_TOOL[$i]}"
        else
            sudo npm -g install "${LCL_PACKAGE[$i]}"
        fi
        PrintTrace "$$TRACE_INFO"  "\n------------------------\n${LCL_TOOL[$i]} - VERSION\n------------------------"
        ${LCL_TOOL[$i]} --version || exit $?
        PrintTrace "$$TRACE_INFO"  "${YLW}----------------------------------------------------------------------${NC}"
        echo
    done
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
}


# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------
# include common library, fail if does not exist
if [ -f "$COMMON_LIB_FILE" ]; then
# shellcheck disable=SC1091
# shellcheck source=../common-lib.sh
    source "$COMMON_LIB_FILE"
else
    echo "ERROR: $COMMON_LIB_FILE does not exist in the local directory."
    echo "  $COMMON_LIB_FILE contains common definitions and functions"
    exit 1
fi


echo
PrintTrace "$TRACE_FUNCTION" "-> $0 ($*)"
# shellcheck disable=SC2068
CheckNumberOfParameters $EXPECTED_NUMBER_OF_PARAMS $@ || PrintUsageAndExitWithCode "$EXIT_CODE_INVALID_NUMBER_OF_PARAMETERS" "${RED}ERROR: Invalid number of parameters.${NC}"


if [ "$ABK_UNIX_TYPE" = "mac" ]; then
    InstallRequiredToolsUsingBrew || exit $?
elif [ "$ABK_UNIX_TYPE" = "linux" ]; then
    InstallRequiredToolsUsingApt || exit $?
fi
InstallRequiredToolsUsingNpm || exit $?


PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
