// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { StakingEligibility, IERC20 } from "src/StakingEligibility.sol";
import { DeployImplementation } from "script/StakingEligibility.s.sol";
import { HatsModuleFactory, IHats } from "hats-module/HatsModuleFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingEligibilityTest is Test, DeployImplementation {
  // variables inherited from DeployImplementation script
  // StakingEligibility public implementation;
  // bytes32 public SALT = bytes32(abi.encode(0x4a75)); // ~ H(4) A(a) T(7) S(5)

  // other test variables
  IHats public constant hats = IHats(0x9D2dfd6066d5935267291718E8AA16C8Ab729E9d); // v1.hatsprotocol.eth
  HatsModuleFactory public factory;
  StakingEligibility public instance;
  StakingEligibilityHarness public harnessImpl;
  StakingEligibilityHarness public harnessInstance;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 16_947_805; // the block number where v1.hatsprotocol.eth was deployed
  string public FACTORY_VERSION = "factory test version";
  string public MODULE_VERSION = "module test version";

  bytes public initData;
  bytes public otherImmutableArgs;
  uint256 public tophat1;
  address public token;
  uint248 public minStake;
  uint256 public stakerHat;
  uint256 public judgeHat;
  uint256 public recipientHat;
  address public dao = makeAddr("dao");
  address public staker1 = makeAddr("staker1");
  address public staker2 = makeAddr("staker2");
  address public judge = makeAddr("judge");
  address public recipient = makeAddr("recipient");
  address public nonWearer = makeAddr("nonWearer");
  address public defaultModule = address(0x4a75);

  uint248 public amount;
  uint248 public totalStaked;
  uint248 public totalSlashed;
  uint248 public stakerStake;
  bool public stakerSlashed;
  uint256 public stakerBalance;
  uint256 public instanceBalance;
  uint248 public expTotalStaked;
  uint248 public expTotalSlashed;
  uint248 public expStakerStake;
  bool public expStakerSlashed;
  uint256 public expStakerBalance;
  uint256 public expInstanceBalance;

  error StakingEligibility_InsufficientStake();
  error StakingEligibility_AlreadySlashed();
  error StakingEligibility_NotJudge();
  error StakingEligibility_NotRecipient();
  error StakingEligibility_NotHatAdmin();
  error StakingEligibility_HatImmutable();
  error StakingEligibility_TransferFailed();
  error StakingEligibility_NothingToWithdraw();

  event StakingEligibility_Deployed(
    uint256 hatId, address instance, address token, uint248 _minStake, uint256 _judgeHat, uint256 _recipientHat
  );
  event StakingEligibility_Staked(address staker, uint248 amount);
  event StakingEligibility_Slashed(address wearer, uint248 amount);
  event StakingEligibility_MinStakeChanged(uint248 newMinStake);
  event StakingEligibility_JudgeHatChanged(uint256 newJudgeHat);
  event StakingEligibility_RecipientHatChanged(uint256 newRecipientHat);

  event Transfer(address indexed from, address indexed to, uint256 value);

  function setUp() public virtual {
    // create and activate a mainnet fork
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy the clone factory
    factory = new HatsModuleFactory{ salt: SALT}(hats, FACTORY_VERSION);

    // deploy the implementation via script
    DeployImplementation.prepare(MODULE_VERSION, false); // set to true to log deployment addresses
    DeployImplementation.run();

    // set up the dao's hats
    vm.startPrank(dao);
    tophat1 = hats.mintTopHat(dao, "tophat1", "");
    judgeHat = hats.createHat(tophat1, "judge", 1, defaultModule, defaultModule, true, "");
    recipientHat = hats.createHat(tophat1, "recipient", 1, defaultModule, defaultModule, true, "");
    stakerHat = hats.createHat(tophat1, "must stake to wear", 5, defaultModule, defaultModule, true, "");
    hats.mintHat(judgeHat, judge);
    hats.mintHat(recipientHat, recipient);
    vm.stopPrank();
  }

  function deployInstance(uint256 _hatId, address _token, uint248 _minStake, uint256 _judgeHat, uint256 _recipientHat)
    public
    virtual
  {
    // encode the other immutable args
    otherImmutableArgs = abi.encodePacked(_token);
    // encode the init data
    initData = abi.encode(_minStake, _judgeHat, _recipientHat);
    // deploy the instance
    instance =
      StakingEligibility(factory.createHatsModule(address(implementation), _hatId, otherImmutableArgs, initData));
  }
}

contract WithInstanceTest is StakingEligibilityTest {
  uint248 public _minStake;
  uint256 public _judgeHat;
  uint256 public _recipientHat;

  function setUp() public virtual override {
    super.setUp();
    // set deploy params
    token = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
    minStake = 1000;

    // deploy the instance
    deployInstance(stakerHat, token, minStake, judgeHat, recipientHat);

    // change the stakerHat's eligibility to instance
    vm.prank(dao);
    hats.changeHatEligibility(stakerHat, address(instance));

    // mint some tokens to the stakers

    deal(token, staker2, 100_000);
  }

  function recordPrelimValues(address _staker) public {
    totalStaked = instance.totalValidStakes();
    totalSlashed = instance.totalSlashedStakes();
    (stakerStake, stakerSlashed) = instance.stakes(_staker);
    stakerBalance = IERC20(token).balanceOf(_staker);
    instanceBalance = IERC20(token).balanceOf(address(instance));
  }

  function stateAssertions(address _staker) public {
    assertEq(instance.totalValidStakes(), expTotalStaked, "totalStaked");
    assertEq(instance.totalSlashedStakes(), expTotalSlashed, "totalSlashedStakes");
    (stakerStake, stakerSlashed) = instance.stakes(_staker);
    assertEq(stakerStake, expStakerStake, "stakerStake");
    assertEq(stakerSlashed, expStakerSlashed, "stakerSlashed");
    assertEq(IERC20(token).balanceOf(_staker), expStakerBalance, "stakerBalance");
    assertEq(IERC20(token).balanceOf(address(instance)), expInstanceBalance, "instanceBalance");
  }

  function stake(address _staker, uint248 _amount) public {
    // ensure the caller has enough tokens
    deal(token, _staker, _amount);
    // approve the instance to spend the staker's tokens
    vm.prank(_staker);
    IERC20(token).approve(address(instance), _amount);
    // submit the stake from the caller
    vm.prank(_staker);
    instance.stake(_amount);
  }
}

contract StakingEligibilityHarness is StakingEligibility {
  constructor(string memory _version) StakingEligibility(_version) { }

  function isMutable() public view hatIsMutable returns (bool) {
    return true;
  }

  function isHatAdmin() public view onlyHatAdmin returns (bool) {
    return true;
  }
}

contract HarnessTest is StakingEligibilityTest {
  StakingEligibilityHarness public harness;

  function setUp() public virtual override {
    super.setUp();
    // deploy the harness implementation
    harnessImpl = new StakingEligibilityHarness("harness version");
    // deploy an instance of the harness and initialize it with the same initData as `instance`
    harnessInstance =
      StakingEligibilityHarness(factory.createHatsModule(address(harnessImpl), stakerHat, otherImmutableArgs, initData));
  }
}

contract Internal_hatIsMutable is HarnessTest {
  function test_mutable_succeeds() public {
    assertTrue(harnessInstance.isMutable());
  }

  function test_immutable_reverts() public {
    // change the stakerHat to be immutable
    vm.prank(dao);
    hats.makeHatImmutable(stakerHat);
    // expect a revert
    vm.expectRevert(StakingEligibility_HatImmutable.selector);
    harnessInstance.isMutable();
  }
}

contract Internal_onlyHatAdmin is HarnessTest {
  function test_hatAdmin_succeeds() public {
    vm.prank(dao);
    assertTrue(harnessInstance.isHatAdmin());
  }

  function test_nonHatAdmin_reverts() public {
    // expect a revert
    vm.expectRevert(StakingEligibility_NotHatAdmin.selector);
    vm.prank(nonWearer);
    harnessInstance.isHatAdmin();
  }
}

contract Constructor is StakingEligibilityTest {
  function test_version__() public {
    // version_ is the value in the implementation contract
    assertEq(implementation.version_(), MODULE_VERSION, "implementation version");
  }

  function test_version_reverts() public {
    vm.expectRevert();
    implementation.version();
  }
}

contract SetUp is WithInstanceTest {
  function test_minStake() public {
    assertEq(instance.minStake(), minStake, "minStake");
  }

  function test_judgeHat() public {
    assertEq(instance.judgeHat(), judgeHat, "judgeHat");
  }

  function test_recipientHat() public {
    assertEq(instance.recipientHat(), recipientHat, "recipientHat");
  }

  function test_otherStateVars_areEmpty() public {
    assertEq(instance.totalValidStakes(), 0, "totalStaked");
    assertEq(instance.totalSlashedStakes(), 0, "totalSlashedStakes");
  }

  function test_emitDeployedEvent() public {
    // prepare to deploy a new instance for a different hat
    stakerHat = 1;
    // predict the new instance address
    address predicted = factory.getHatsModuleAddress(address(implementation), stakerHat, otherImmutableArgs);
    // expect the event
    vm.expectEmit(true, true, true, true);
    emit StakingEligibility_Deployed(stakerHat, predicted, token, minStake, judgeHat, recipientHat);

    deployInstance(stakerHat, token, minStake, judgeHat, recipientHat);
  }
}

contract GetWearerStatus is WithInstanceTest {
  bool public eligible;
  bool public standing;

  function test_atMinStake_true_true() public {
    amount = minStake;
    stake(staker1, amount);

    (eligible, standing) = instance.getWearerStatus(staker1, 0);

    assertEq(eligible, true, "eligible");
    assertEq(standing, true, "standing");
  }

  function test_overMinStake_true_true() public {
    amount = minStake + 1;
    stake(staker1, amount);

    (eligible, standing) = instance.getWearerStatus(staker1, 0);

    assertEq(eligible, true, "eligible");
    assertEq(standing, true, "standing");
  }

  function test_underMinStake_false_true() public {
    amount = minStake - 1;
    stake(staker1, amount);

    (eligible, standing) = instance.getWearerStatus(staker1, 0);

    assertEq(eligible, false, "eligible");
    assertEq(standing, true, "standing");
  }

  function test_slashed_false_false(uint248 _amount) public {
    amount = _amount;

    stake(staker1, amount);
    // slash
    vm.prank(judge);
    instance.slash(staker1);

    (eligible, standing) = instance.getWearerStatus(staker1, 0);

    assertEq(eligible, false, "eligible");
    assertEq(standing, false, "standing");
  }

  function test_minStakeIncreasedOverStake_false_true() public {
    amount = minStake;
    stake(staker1, amount);

    // increase the minStake
    _minStake = minStake + 1;
    vm.prank(dao);
    instance.changeMinStake(_minStake);

    (eligible, standing) = instance.getWearerStatus(staker1, 0);

    assertEq(eligible, false, "eligible");
    assertEq(standing, true, "standing");
  }
}

contract Staking is WithInstanceTest {
  function stakeTest(address _staker, uint248 _amount, bool _approved) public {
    recordPrelimValues(_staker);

    if (stakerSlashed) {
      // expect a revert
      vm.expectRevert(StakingEligibility_AlreadySlashed.selector);
    } else if (!_approved) {
      // expect a revert
      vm.expectRevert();
    } else {
      // approve the instance to spend the staker's tokens
      vm.prank(_staker);
      IERC20(token).approve(address(instance), _amount);
      // expect the Staked event
      vm.expectEmit(true, true, true, true);
      emit StakingEligibility_Staked(_staker, _amount);
    }

    // submit the stake from the caller
    vm.prank(_staker);
    instance.stake(_amount);

    // set expected post values
    if (stakerSlashed || !_approved) {
      // expect no change
      expTotalStaked = totalStaked;
      expTotalSlashed = totalSlashed;
      expStakerStake = stakerStake;
      expStakerSlashed = stakerSlashed;
      expStakerBalance = uint256(stakerBalance);
      expInstanceBalance = uint256(instanceBalance);
    } else {
      // expect stake vars to change
      expTotalStaked = totalStaked + _amount;
      expTotalSlashed = totalSlashed;
      expStakerStake = stakerStake + _amount;
      expStakerSlashed = stakerSlashed;
      expStakerBalance = stakerBalance - uint256(_amount);
      expInstanceBalance = instanceBalance + uint256(_amount);
    }

    stateAssertions(_staker);
  }

  function test_firstStake_happy(uint248 _amount) public {
    deal(token, staker1, _amount, true);
    stakeTest(staker1, _amount, true);
  }

  function test_stakeTwice_happy() public {
    amount = 1000;
    deal(token, staker1, amount * 3);
    stakeTest(staker1, amount, true);
    stakeTest(staker1, amount + 1, true);
  }

  function test_secondStaker_happy() public {
    amount = 1000;
    deal(token, staker1, amount);
    stakeTest(staker1, amount, true);
    // second staker stakes
    amount = 1005;
    deal(token, staker2, amount);
    stakeTest(staker2, amount, true);
  }

  function test_stake_unapproved_reverts() public {
    amount = 1000;
    deal(token, staker1, amount);
    stakeTest(staker1, amount, false);
  }

  function test_stake_slashed_reverts() public {
    amount = 1000;
    deal(token, staker1, amount);
    stakeTest(staker1, amount, true);

    // slash the staker
    vm.prank(judge);
    instance.slash(staker1);

    // try to stake again
    stakeTest(staker1, amount, true);
  }

  function test_stakeTwice_TooMuch_reverts() public {
    amount = type(uint248).max;
    deal(token, staker1, amount);
    stakeTest(staker1, amount, true);

    amount = 1000; // will take amount over the max
    deal(token, staker1, amount);
    vm.prank(staker1);
    IERC20(token).approve(address(instance), amount);
    // expect a revert due to overflow
    vm.expectRevert();
    vm.prank(staker1);
    instance.stake(amount);
  }
}

contract Unstaking is WithInstanceTest {
  function unstakeTest(address _staker, uint248 _amount, bool _sufficient) public {
    recordPrelimValues(_staker);

    if (!_sufficient) {
      vm.expectRevert(StakingEligibility_InsufficientStake.selector);
    } else {
      vm.expectEmit(true, true, true, true);
      emit Transfer(address(instance), _staker, _amount);
    }

    vm.prank(_staker);
    instance.unstake(_amount);

    // set expected post values
    if (!_sufficient) {
      // expect no change
      expTotalStaked = totalStaked;
      expTotalSlashed = totalSlashed;
      expStakerStake = stakerStake;
      expStakerSlashed = stakerSlashed;
      expStakerBalance = stakerBalance;
      expInstanceBalance = instanceBalance;
    } else {
      // expect stake vars to change
      expTotalStaked = totalStaked - _amount;
      expTotalSlashed = totalSlashed;
      expStakerStake = stakerStake - _amount;
      expStakerSlashed = stakerSlashed;
      expStakerBalance = stakerBalance + uint256(_amount);
      expInstanceBalance = instanceBalance - uint256(_amount);
    }

    stateAssertions(_staker);
  }

  function test_unstake_sameAmount() public {
    amount = 1000;
    stake(staker1, amount);

    // unstake
    unstakeTest(staker1, amount, true);
  }

  function test_unstake_smallerAmount() public {
    amount = 1000;
    stake(staker1, amount);

    // unstake a lower amount
    unstakeTest(staker1, amount - 50, true);
  }

  function test_unstake_tooMuch_reverts() public {
    amount = 1000;
    stake(staker1, amount);

    // unstake a higher amount
    unstakeTest(staker1, amount + 1, false);
  }

  function test_unstake_slashed_reverts() public {
    amount = 1000;
    stake(staker1, amount);
    // slash
    vm.prank(judge);
    instance.slash(staker1);

    // unstake a higher amount
    unstakeTest(staker1, amount, false);
  }
}

contract Slashing is WithInstanceTest {
  function slashTest(address _staker, bool _judge, bool _notSlashed) public {
    recordPrelimValues(staker1);

    if (!_judge) {
      vm.expectRevert(StakingEligibility_NotJudge.selector);
    } else if (!_notSlashed) {
      vm.expectRevert(StakingEligibility_AlreadySlashed.selector);
      vm.prank(judge);
    } else {
      vm.expectEmit(true, true, true, true);
      emit StakingEligibility_Slashed(_staker, stakerStake);
      vm.prank(judge);
    }

    // slash
    instance.slash(staker1);

    // set expected post values
    if (!_judge) {
      // expect no change
      expTotalStaked = totalStaked;
      expTotalSlashed = totalSlashed;
      expStakerStake = stakerStake;
      expStakerSlashed = stakerSlashed;
      expStakerBalance = stakerBalance;
      expInstanceBalance = instanceBalance;
    } else {
      // expect stake and slashed vars to change
      expTotalStaked = totalStaked - stakerStake;
      expTotalSlashed = totalSlashed + stakerStake;
      expStakerStake = stakerStake - stakerStake;
      expStakerSlashed = true;
      expStakerBalance = stakerBalance;
      expInstanceBalance = instanceBalance;
    }

    stateAssertions(_staker);
  }

  function test_slash_happy() public {
    amount = 1000;
    stake(staker1, amount);

    slashTest(staker1, true, true);
  }

  function test_unstaked_canStillSlash() public {
    slashTest(staker1, true, true);
  }

  function test_notJudge_reverts() public {
    amount = 1000;
    stake(staker1, amount);

    slashTest(staker1, false, true);
  }

  function test_alreadySlashed_reverts() public {
    amount = 1000;
    stake(staker1, amount);

    // slash
    vm.prank(judge);
    instance.slash(staker1);

    slashTest(staker1, true, false);
  }
}

contract Withdrawing is WithInstanceTest {
  function withdrawTest(address _to, bool _recipient, bool _somethingToWithdraw) public {
    totalStaked = instance.totalValidStakes();
    totalSlashed = instance.totalSlashedStakes();
    instanceBalance = IERC20(token).balanceOf(address(instance));

    if (!_somethingToWithdraw) {
      vm.expectRevert(StakingEligibility_NothingToWithdraw.selector);
    } else if (!_recipient) {
      vm.expectRevert(StakingEligibility_NotRecipient.selector);
    } else {
      vm.expectEmit(true, true, true, true);
      emit Transfer(address(instance), _to, totalSlashed);
    }

    // withdraw
    instance.withdraw(_to);

    // set expected post values
    if (!_recipient) {
      // expect no change
      expTotalStaked = totalStaked;
      expTotalSlashed = totalSlashed;
      expInstanceBalance = instanceBalance;
    } else {
      // expect slashed vars to change
      expTotalStaked = totalStaked;
      expTotalSlashed = 0;
      expInstanceBalance = instanceBalance - totalSlashed;
    }

    assertEq(instance.totalValidStakes(), expTotalStaked, "totalStaked");
    assertEq(instance.totalSlashedStakes(), expTotalSlashed, "totalSlashedStakes");
    assertEq(IERC20(token).balanceOf(address(instance)), expInstanceBalance, "instanceBalance");
  }

  function test_withdraw_happy() public {
    // stake
    amount = 1000;
    stake(staker1, amount);
    // slash
    vm.prank(judge);
    instance.slash(staker1);

    withdrawTest(recipient, true, true);
  }

  function test_notRecipient_reverts() public {
    // stake
    amount = 1000;
    stake(staker1, amount);
    // slash
    vm.prank(judge);
    instance.slash(staker1);

    withdrawTest(nonWearer, false, true);
  }

  function test_nothingToWithdraw_reverts() public {
    // stake
    amount = 1000;
    stake(staker1, amount);

    // attempt withdraw
    withdrawTest(recipient, true, false);
  }
}

contract ChangeMinStake is WithInstanceTest {
  function test_changeMinStake_happy() public {
    _minStake = minStake + 1;
    vm.expectEmit(true, true, true, true);
    emit StakingEligibility_MinStakeChanged(_minStake);
    vm.prank(dao);
    instance.changeMinStake(_minStake);
    assertEq(instance.minStake(), _minStake, "minStake");
  }

  function test_changeMinStake_notHatAdmin_reverts() public {
    _minStake = minStake + 1;
    vm.expectRevert(StakingEligibility_NotHatAdmin.selector);
    vm.prank(nonWearer);
    instance.changeMinStake(_minStake);
  }

  function test_changeMinStake_hatNotMutable_reverts() public {
    // change the stakerHat to be immutable
    vm.prank(dao);
    hats.makeHatImmutable(stakerHat);
    // expect a revert
    vm.expectRevert(StakingEligibility_HatImmutable.selector);
    vm.prank(dao);
    instance.changeMinStake(_minStake);
  }
}

contract ChangeJudgeHat is WithInstanceTest {
  function test_changeJudgeHat_happy() public {
    _judgeHat = judgeHat + 1;
    vm.expectEmit(true, true, true, true);
    emit StakingEligibility_JudgeHatChanged(_judgeHat);
    vm.prank(dao);
    instance.changeJudgeHat(_judgeHat);
    assertEq(instance.judgeHat(), _judgeHat, "judgeHat");
  }

  function test_changeJudgeHat_notHatAdmin_reverts() public {
    _judgeHat = judgeHat + 1;
    vm.expectRevert(StakingEligibility_NotHatAdmin.selector);
    vm.prank(nonWearer);
    instance.changeJudgeHat(_judgeHat);
  }

  function test_changeJudgeHat_hatNotMutable_reverts() public {
    // change the stakerHat to be immutable
    vm.prank(dao);
    hats.makeHatImmutable(stakerHat);
    // expect a revert
    vm.expectRevert(StakingEligibility_HatImmutable.selector);
    vm.prank(dao);
    instance.changeJudgeHat(_judgeHat);
  }
}

contract ChangeRecipientHat is WithInstanceTest {
  function test_changeRecipientHat_happy() public {
    _recipientHat = recipientHat + 1;
    vm.expectEmit(true, true, true, true);
    emit StakingEligibility_RecipientHatChanged(_recipientHat);
    vm.prank(dao);
    instance.changeRecipientHat(_recipientHat);
    assertEq(instance.recipientHat(), _recipientHat, "recipientHat");
  }

  function test_changeRecipientHat_notHatAdmin_reverts() public {
    _recipientHat = recipientHat + 1;
    vm.expectRevert(StakingEligibility_NotHatAdmin.selector);
    vm.prank(nonWearer);
    instance.changeRecipientHat(_recipientHat);
  }

  function test_changeRecipientHat_hatNotMutable_reverts() public {
    // change the stakerHat to be immutable
    vm.prank(dao);
    hats.makeHatImmutable(stakerHat);
    // expect a revert
    vm.expectRevert(StakingEligibility_HatImmutable.selector);
    vm.prank(dao);
    instance.changeRecipientHat(_recipientHat);
  }
}
