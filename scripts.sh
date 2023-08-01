FUNCTION=$1
CONTRACT_ADDRESS="0x4477072c2c9867029b336fd96e27c8f33fcf56088dc3245fce4905e4646e2286"
ADMIN_ADDRESS="0x1764fd45317bbddc6379f22c6c72b52a138bf0e2db76297e81146cacf7bc42c5"
TRIGGER_ADDRESS="0xc5cb1f1ce6951226e9c46ce8d42eda1ac9774a0fef91e2910939119ef0c95568"

function chaddr() {
  aptos move run --function-id $CONTRACT_ADDRESS::main::set_addresses --args address:$ADMIN_ADDRESS address:$TRIGGER_ADDRESS
}


if [[ $FUNCTION == "" ]]; then
    echo "input function name"
else
    $FUNCTION
fi
