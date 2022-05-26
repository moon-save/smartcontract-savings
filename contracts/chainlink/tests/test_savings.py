from brownie import exceptions
from scripts.helpful_scripts import get_account, fund_with_link, get_contract
from scripts.deploy_lottery import deploy_lottery

import pytest
import time

def test_get_lottery_id():
    savings = deploy_lottery()
    savingsID = savings.getLotteryID()
    assert savingsID == 0

def test_cannot_enter():
    savings = deploy_lottery()

    with pytest.raises(exceptions.VirtualMachineError):
        savings.depositSavings(0, {"from": get_account(), "value": 10})


def test_can_enter_savings():
    savings = deploy_lottery()
    savings.createLottery(1, 30, {"from": get_account()})
    savings.depositSavings(0, {"from": get_account(), "value": 10})

    assert savings.getPlayersCount() == 1


def test_can_pick_winner():
    savings = deploy_lottery()
    savings.createLottery(1, 4, {"from": get_account()})
    
    savings.depositSavings(0, {"from": get_account(), "value": 15})
    savings.depositSavings(0, {"from": get_account(index=1), "value": 3})
    savings.depositSavings(0, {"from": get_account(index=2), "value": 2})

    savings_balance = savings.balance()
    account_balance = get_account(index=0).balance()

    fund_with_link(savings)
    time.sleep(5)

    transaction = savings.declareWinner(0, {"from": get_account()})
    request_id = transaction.events['RandomnessRequested']['requestId']
    STATIC_RNG = 10
    get_contract("vrf_coordinator").callBackWithRandomness(request_id,
        STATIC_RNG, savings.address, {"from": get_account()})

    # winner is 10 % 17 entries = 10
    # print(f"{get_account(index=0).balance()}, {get_account(index=1).balance()}, {get_account(index=2).balance()}")
    # for winner in savings.getWinners():
    #     print(f"Winner: {winner}")

    assert savings.getWinners()[0] == get_account(index=0)
    assert get_account(index=0).balance() == (savings_balance / 4 * 3) + account_balance
