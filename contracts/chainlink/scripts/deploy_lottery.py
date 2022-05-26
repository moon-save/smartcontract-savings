from scripts.helpful_scripts import get_account, get_contract, fund_with_link
from brownie import SavingsLottery, network, config

def deploy_lottery():
    account= get_account()
    lottery = SavingsLottery.deploy(
        get_contract("vrf_coordinator").address,
        get_contract("link_token").address,
        config["networks"][network.show_active()]["keyhash"],
        config["networks"][network.show_active()]["fee"],
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify", False),
    ) 

    print("Deployed lottery ")
    return lottery

def main():
    deploy_lottery()
