// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TaskBoard} from "../src/TaskBoard.sol";

contract RejectEther {
    receive() external payable {
        revert("no ETH accepted");
    }
}

contract TaskBoardTest is Test {
    TaskBoard public board;

    address founder = address(this);
    address ceo = makeAddr("ceo");
    address contributor1 = makeAddr("contributor1");
    address contributor2 = makeAddr("contributor2");
    address stranger = makeAddr("stranger");

    bytes32 descHash = keccak256("Build a landing page");
    bytes32 contentHash1 = keccak256("ipfs://Qm..submission1");
    bytes32 contentHash2 = keccak256("ipfs://Qm..submission2");

    function setUp() public {
        board = new TaskBoard(ceo);
        vm.deal(ceo, 100 ether);
        vm.deal(contributor1, 1 ether);
        vm.deal(contributor2, 1 ether);
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    function test_constructor_setsFounderAndCeo() public view {
        assertEq(board.founder(), founder);
        assertEq(board.ceo(), ceo);
    }

    function test_constructor_revertsOnZeroCeo() public {
        vm.expectRevert("TaskBoard: CEO cannot be zero address");
        new TaskBoard(address(0));
    }

    // ──────────────────────────────────────────────
    //  createTask
    // ──────────────────────────────────────────────

    function test_createTask_success() public {
        vm.prank(ceo);
        uint256 taskId = board.createTask{value: 1 ether}(
            descHash, 0, TaskBoard.ApprovalMode.CEO
        );

        assertEq(taskId, 0);
        assertEq(board.taskCount(), 1);
        assertEq(board.totalTasksCreated(), 1);
        assertEq(address(board).balance, 1 ether);

        (
            bytes32 dh, uint256 reward, uint256 deadline,
            TaskBoard.ApprovalMode mode, TaskBoard.TaskStatus status,
            uint256 createdAt, address winner, uint256 subCount
        ) = board.getTask(0);

        assertEq(dh, descHash);
        assertEq(reward, 1 ether);
        assertEq(deadline, 0);
        assertEq(uint8(mode), uint8(TaskBoard.ApprovalMode.CEO));
        assertEq(uint8(status), uint8(TaskBoard.TaskStatus.Open));
        assertEq(createdAt, block.timestamp);
        assertEq(winner, address(0));
        assertEq(subCount, 0);
    }

    function test_createTask_withDeadline() public {
        uint256 futureDeadline = block.timestamp + 7 days;
        vm.prank(ceo);
        board.createTask{value: 1 ether}(descHash, futureDeadline, TaskBoard.ApprovalMode.Founder);

        (, , uint256 deadline, TaskBoard.ApprovalMode mode, , , ,) = board.getTask(0);
        assertEq(deadline, futureDeadline);
        assertEq(uint8(mode), uint8(TaskBoard.ApprovalMode.Founder));
    }

    function test_createTask_emitsEvent() public {
        vm.prank(ceo);
        vm.expectEmit(true, false, false, true);
        emit TaskBoard.TaskCreated(0, descHash, 1 ether, 0, TaskBoard.ApprovalMode.CEO);
        board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);
    }

    function test_createTask_revertsIfNotCeo() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert("TaskBoard: caller is not the CEO");
        board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);
    }

    function test_createTask_revertsIfEmptyDescHash() public {
        vm.prank(ceo);
        vm.expectRevert("TaskBoard: empty description hash");
        board.createTask{value: 1 ether}(bytes32(0), 0, TaskBoard.ApprovalMode.CEO);
    }

    function test_createTask_revertsIfZeroValue() public {
        vm.prank(ceo);
        vm.expectRevert("TaskBoard: reward must be greater than zero");
        board.createTask{value: 0}(descHash, 0, TaskBoard.ApprovalMode.CEO);
    }

    function test_createTask_revertsIfDeadlineInPast() public {
        vm.warp(1000);
        vm.prank(ceo);
        vm.expectRevert("TaskBoard: deadline must be in the future");
        board.createTask{value: 1 ether}(descHash, 999, TaskBoard.ApprovalMode.CEO);
    }

    function test_createTask_multipleTasks_incrementsIds() public {
        vm.startPrank(ceo);
        uint256 id0 = board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);
        uint256 id1 = board.createTask{value: 2 ether}(keccak256("task2"), 0, TaskBoard.ApprovalMode.Founder);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(board.taskCount(), 2);
        assertEq(board.totalTasksCreated(), 2);
        assertEq(address(board).balance, 3 ether);
    }

    // ──────────────────────────────────────────────
    //  submitDeliverable
    // ──────────────────────────────────────────────

    function test_submitDeliverable_success() public {
        _createDefaultTask();

        vm.prank(contributor1);
        uint256 subIdx = board.submitDeliverable(0, contentHash1);

        assertEq(subIdx, 0);

        (address c, bytes32 ch, uint256 ts) = board.getSubmission(0, 0);
        assertEq(c, contributor1);
        assertEq(ch, contentHash1);
        assertEq(ts, block.timestamp);
    }

    function test_submitDeliverable_multipleSubmissions() public {
        _createDefaultTask();

        vm.prank(contributor1);
        uint256 idx0 = board.submitDeliverable(0, contentHash1);

        vm.prank(contributor2);
        uint256 idx1 = board.submitDeliverable(0, contentHash2);

        assertEq(idx0, 0);
        assertEq(idx1, 1);

        (, , , , , , , uint256 subCount) = board.getTask(0);
        assertEq(subCount, 2);
    }

    function test_submitDeliverable_emitsEvent() public {
        _createDefaultTask();

        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit TaskBoard.SubmissionReceived(0, 0, contributor1, contentHash1);
        board.submitDeliverable(0, contentHash1);
    }

    function test_submitDeliverable_revertsIfTaskNotExist() public {
        vm.prank(contributor1);
        vm.expectRevert("TaskBoard: task does not exist");
        board.submitDeliverable(99, contentHash1);
    }

    function test_submitDeliverable_revertsIfEmptyContentHash() public {
        _createDefaultTask();

        vm.prank(contributor1);
        vm.expectRevert("TaskBoard: empty content hash");
        board.submitDeliverable(0, bytes32(0));
    }

    function test_submitDeliverable_revertsIfTaskNotOpen() public {
        _createDefaultTask();
        _submitAndApprove(0);

        vm.prank(contributor2);
        vm.expectRevert("TaskBoard: task not open");
        board.submitDeliverable(0, contentHash2);
    }

    function test_submitDeliverable_revertsIfExpired() public {
        uint256 deadline = block.timestamp + 1 days;
        vm.prank(ceo);
        board.createTask{value: 1 ether}(descHash, deadline, TaskBoard.ApprovalMode.CEO);

        vm.warp(deadline + 1);

        vm.prank(contributor1);
        vm.expectRevert("TaskBoard: task expired");
        board.submitDeliverable(0, contentHash1);
    }

    function test_submitDeliverable_atExactDeadline() public {
        uint256 deadline = block.timestamp + 1 days;
        vm.prank(ceo);
        board.createTask{value: 1 ether}(descHash, deadline, TaskBoard.ApprovalMode.CEO);

        vm.warp(deadline);

        vm.prank(contributor1);
        uint256 idx = board.submitDeliverable(0, contentHash1);
        assertEq(idx, 0);
    }

    // ──────────────────────────────────────────────
    //  submitOnBehalfOf
    // ──────────────────────────────────────────────

    function test_submitOnBehalfOf_success() public {
        _createDefaultTask();

        vm.prank(ceo);
        uint256 subIdx = board.submitOnBehalfOf(0, contentHash1, contributor1);

        assertEq(subIdx, 0);

        (address c, bytes32 ch, uint256 ts) = board.getSubmission(0, 0);
        assertEq(c, contributor1);
        assertEq(ch, contentHash1);
        assertEq(ts, block.timestamp);
    }

    function test_submitOnBehalfOf_emitsEvent() public {
        _createDefaultTask();

        vm.prank(ceo);
        vm.expectEmit(true, true, true, true);
        emit TaskBoard.SubmissionReceived(0, 0, contributor1, contentHash1);
        board.submitOnBehalfOf(0, contentHash1, contributor1);
    }

    function test_submitOnBehalfOf_revertsIfNotCeo() public {
        _createDefaultTask();

        vm.prank(stranger);
        vm.expectRevert("TaskBoard: caller is not the CEO");
        board.submitOnBehalfOf(0, contentHash1, contributor1);
    }

    function test_submitOnBehalfOf_revertsIfZeroContributor() public {
        _createDefaultTask();

        vm.prank(ceo);
        vm.expectRevert("TaskBoard: contributor cannot be zero address");
        board.submitOnBehalfOf(0, contentHash1, address(0));
    }

    function test_submitOnBehalfOf_approveAndWithdraw() public {
        _createDefaultTask();

        // CEO submits on behalf of contributor1
        vm.prank(ceo);
        board.submitOnBehalfOf(0, contentHash1, contributor1);

        // CEO approves
        vm.prank(ceo);
        board.approveSubmission(0, 0);

        // contributor1 can withdraw
        assertEq(board.pendingWithdrawals(contributor1), 1 ether);

        uint256 balBefore = contributor1.balance;
        vm.prank(contributor1);
        board.withdraw();
        assertEq(contributor1.balance, balBefore + 1 ether);
    }

    // ──────────────────────────────────────────────
    //  approveSubmission
    // ──────────────────────────────────────────────

    function test_approveSubmission_ceoMode() public {
        _createDefaultTask();

        vm.prank(contributor1);
        board.submitDeliverable(0, contentHash1);

        vm.prank(ceo);
        board.approveSubmission(0, 0);

        (, uint256 reward, , , TaskBoard.TaskStatus status, , address winner,) = board.getTask(0);
        assertEq(uint8(status), uint8(TaskBoard.TaskStatus.Completed));
        assertEq(winner, contributor1);
        assertEq(reward, 0);
        assertEq(board.pendingWithdrawals(contributor1), 1 ether);
        assertEq(board.totalPaidOut(), 1 ether);
    }

    function test_approveSubmission_founderMode() public {
        vm.prank(ceo);
        board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.Founder);

        vm.prank(contributor1);
        board.submitDeliverable(0, contentHash1);

        // founder = address(this)
        board.approveSubmission(0, 0);

        (, , , , TaskBoard.TaskStatus status, , address winner,) = board.getTask(0);
        assertEq(uint8(status), uint8(TaskBoard.TaskStatus.Completed));
        assertEq(winner, contributor1);
    }

    function test_approveSubmission_emitsEvents() public {
        _createDefaultTask();

        vm.prank(contributor1);
        board.submitDeliverable(0, contentHash1);

        vm.prank(ceo);
        vm.expectEmit(true, false, false, true);
        emit TaskBoard.TaskStatusChanged(0, TaskBoard.TaskStatus.Open, TaskBoard.TaskStatus.Completed);
        vm.expectEmit(true, true, true, true);
        emit TaskBoard.SubmissionApproved(0, 0, contributor1, 1 ether);
        board.approveSubmission(0, 0);
    }

    function test_approveSubmission_afterDeadline() public {
        uint256 deadline = block.timestamp + 1 days;
        vm.prank(ceo);
        board.createTask{value: 1 ether}(descHash, deadline, TaskBoard.ApprovalMode.CEO);

        vm.prank(contributor1);
        board.submitDeliverable(0, contentHash1);

        vm.warp(deadline + 100);

        vm.prank(ceo);
        board.approveSubmission(0, 0);

        (, , , , TaskBoard.TaskStatus status, , ,) = board.getTask(0);
        assertEq(uint8(status), uint8(TaskBoard.TaskStatus.Completed));
    }

    function test_approveSubmission_revertsIfNotCeoInCeoMode() public {
        _createDefaultTask();

        vm.prank(contributor1);
        board.submitDeliverable(0, contentHash1);

        vm.prank(stranger);
        vm.expectRevert("TaskBoard: only CEO can approve this task");
        board.approveSubmission(0, 0);
    }

    function test_approveSubmission_revertsIfNotFounderInFounderMode() public {
        vm.prank(ceo);
        board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.Founder);

        vm.prank(contributor1);
        board.submitDeliverable(0, contentHash1);

        vm.prank(ceo);
        vm.expectRevert("TaskBoard: only founder can approve this task");
        board.approveSubmission(0, 0);
    }

    function test_approveSubmission_revertsIfTaskNotExist() public {
        vm.prank(ceo);
        vm.expectRevert("TaskBoard: task does not exist");
        board.approveSubmission(99, 0);
    }

    function test_approveSubmission_revertsIfTaskNotOpen() public {
        _createDefaultTask();

        vm.prank(contributor1);
        board.submitDeliverable(0, contentHash1);

        // Approve once (completes the task)
        vm.prank(ceo);
        board.approveSubmission(0, 0);

        // Try approving again on the now-completed task
        vm.prank(ceo);
        vm.expectRevert("TaskBoard: task not open");
        board.approveSubmission(0, 0);
    }

    function test_approveSubmission_revertsIfSubmissionNotExist() public {
        _createDefaultTask();

        vm.prank(ceo);
        vm.expectRevert("TaskBoard: submission does not exist");
        board.approveSubmission(0, 0);
    }

    // ──────────────────────────────────────────────
    //  cancelTask
    // ──────────────────────────────────────────────

    function test_cancelTask_byCeo() public {
        _createDefaultTask();

        uint256 ceoBefore = ceo.balance;

        vm.prank(ceo);
        board.cancelTask(0);

        (, uint256 reward, , , TaskBoard.TaskStatus status, , ,) = board.getTask(0);
        assertEq(uint8(status), uint8(TaskBoard.TaskStatus.Cancelled));
        assertEq(reward, 0);
        assertEq(ceo.balance, ceoBefore + 1 ether);
        assertEq(address(board).balance, 0);
    }

    function test_cancelTask_byFounder() public {
        _createDefaultTask();

        uint256 ceoBefore = ceo.balance;

        // founder = address(this)
        board.cancelTask(0);

        assertEq(ceo.balance, ceoBefore + 1 ether);
    }

    function test_cancelTask_emitsEvents() public {
        _createDefaultTask();

        vm.prank(ceo);
        vm.expectEmit(true, false, false, true);
        emit TaskBoard.TaskStatusChanged(0, TaskBoard.TaskStatus.Open, TaskBoard.TaskStatus.Cancelled);
        vm.expectEmit(true, true, true, true);
        emit TaskBoard.TaskCancelled(0, ceo, ceo, 1 ether);
        board.cancelTask(0);
    }

    function test_cancelTask_revertsIfNotAuthorized() public {
        _createDefaultTask();

        vm.prank(stranger);
        vm.expectRevert("TaskBoard: unauthorized cancel");
        board.cancelTask(0);
    }

    function test_cancelTask_revertsIfTaskNotExist() public {
        vm.prank(ceo);
        vm.expectRevert("TaskBoard: task does not exist");
        board.cancelTask(99);
    }

    function test_cancelTask_revertsIfAlreadyCancelled() public {
        _createDefaultTask();

        vm.prank(ceo);
        board.cancelTask(0);

        vm.prank(ceo);
        vm.expectRevert("TaskBoard: task not open");
        board.cancelTask(0);
    }

    function test_cancelTask_revertsIfCompleted() public {
        _createDefaultTask();
        _submitAndApprove(0);

        vm.prank(ceo);
        vm.expectRevert("TaskBoard: task not open");
        board.cancelTask(0);
    }

    function test_cancelTask_revertsIfRefundFails() public {
        // Set CEO to a contract that rejects ETH
        RejectEther rejector = new RejectEther();
        vm.deal(address(rejector), 10 ether);
        board.setCeo(address(rejector));

        vm.prank(address(rejector));
        board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);

        // Founder cancels — refund goes to CEO (rejector), which reverts
        vm.expectRevert("TaskBoard: refund failed");
        board.cancelTask(0);
    }

    // ──────────────────────────────────────────────
    //  withdraw
    // ──────────────────────────────────────────────

    function test_withdraw_success() public {
        _createDefaultTask();
        _submitAndApprove(0);

        uint256 balBefore = contributor1.balance;

        vm.prank(contributor1);
        board.withdraw();

        assertEq(contributor1.balance, balBefore + 1 ether);
        assertEq(board.pendingWithdrawals(contributor1), 0);
    }

    function test_withdraw_emitsEvent() public {
        _createDefaultTask();
        _submitAndApprove(0);

        vm.prank(contributor1);
        vm.expectEmit(true, false, false, true);
        emit TaskBoard.Withdrawal(contributor1, 1 ether);
        board.withdraw();
    }

    function test_withdraw_accumulatesAcrossMultipleTasks() public {
        vm.startPrank(ceo);
        board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);
        board.createTask{value: 2 ether}(keccak256("task2"), 0, TaskBoard.ApprovalMode.CEO);
        vm.stopPrank();

        vm.prank(contributor1);
        board.submitDeliverable(0, contentHash1);
        vm.prank(contributor1);
        board.submitDeliverable(1, contentHash1);

        vm.startPrank(ceo);
        board.approveSubmission(0, 0);
        board.approveSubmission(1, 0);
        vm.stopPrank();

        assertEq(board.pendingWithdrawals(contributor1), 3 ether);

        uint256 balBefore = contributor1.balance;
        vm.prank(contributor1);
        board.withdraw();

        assertEq(contributor1.balance, balBefore + 3 ether);
    }

    function test_withdraw_revertsIfNoPending() public {
        vm.prank(stranger);
        vm.expectRevert("TaskBoard: no funds to withdraw");
        board.withdraw();
    }

    function test_withdraw_revertsIfTransferFails() public {
        _createDefaultTask();

        // Submit from a contract that rejects ETH
        RejectEther rejector = new RejectEther();
        vm.prank(address(rejector));
        board.submitDeliverable(0, contentHash1);

        vm.prank(ceo);
        board.approveSubmission(0, 0);

        vm.prank(address(rejector));
        vm.expectRevert("TaskBoard: withdrawal failed");
        board.withdraw();
    }

    // ──────────────────────────────────────────────
    //  setCeo
    // ──────────────────────────────────────────────

    function test_setCeo_success() public {
        address newCeo = makeAddr("newCeo");
        board.setCeo(newCeo);
        assertEq(board.ceo(), newCeo);
    }

    function test_setCeo_emitsEvent() public {
        address newCeo = makeAddr("newCeo");
        vm.expectEmit(true, true, false, false);
        emit TaskBoard.CeoUpdated(ceo, newCeo);
        board.setCeo(newCeo);
    }

    function test_setCeo_revertsIfNotFounder() public {
        vm.prank(ceo);
        vm.expectRevert("TaskBoard: caller is not the founder");
        board.setCeo(makeAddr("newCeo"));
    }

    function test_setCeo_revertsIfZeroAddress() public {
        vm.expectRevert("TaskBoard: CEO cannot be zero address");
        board.setCeo(address(0));
    }

    // ──────────────────────────────────────────────
    //  View functions
    // ──────────────────────────────────────────────

    function test_getTask_revertsIfNotExist() public {
        vm.expectRevert("TaskBoard: task does not exist");
        board.getTask(0);
    }

    function test_getSubmission_revertsIfTaskNotExist() public {
        vm.expectRevert("TaskBoard: task does not exist");
        board.getSubmission(0, 0);
    }

    function test_getSubmission_revertsIfSubmissionNotExist() public {
        _createDefaultTask();
        vm.expectRevert("TaskBoard: submission does not exist");
        board.getSubmission(0, 0);
    }

    function test_getTaskIdsInRange_basic() public {
        vm.startPrank(ceo);
        board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);
        board.createTask{value: 1 ether}(keccak256("t2"), 0, TaskBoard.ApprovalMode.CEO);
        board.createTask{value: 1 ether}(keccak256("t3"), 0, TaskBoard.ApprovalMode.CEO);
        vm.stopPrank();

        uint256[] memory ids = board.getTaskIdsInRange(0, 3);
        assertEq(ids.length, 3);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);
        assertEq(ids[2], 2);
    }

    function test_getTaskIdsInRange_subset() public {
        vm.startPrank(ceo);
        for (uint256 i = 0; i < 5; i++) {
            board.createTask{value: 1 ether}(keccak256(abi.encode(i)), 0, TaskBoard.ApprovalMode.CEO);
        }
        vm.stopPrank();

        uint256[] memory ids = board.getTaskIdsInRange(1, 4);
        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(ids[2], 3);
    }

    function test_getTaskIdsInRange_clampsEnd() public {
        _createDefaultTask();

        uint256[] memory ids = board.getTaskIdsInRange(0, 100);
        assertEq(ids.length, 1);
        assertEq(ids[0], 0);
    }

    function test_getTaskIdsInRange_emptyRange() public {
        _createDefaultTask();
        uint256[] memory ids = board.getTaskIdsInRange(1, 1);
        assertEq(ids.length, 0);
    }

    function test_getTaskIdsInRange_revertsIfInvalidRange() public {
        vm.expectRevert("TaskBoard: invalid range");
        board.getTaskIdsInRange(5, 3);
    }

    function test_getTaskIdsInRange_revertsIfStartOutOfBounds() public {
        _createDefaultTask();
        vm.expectRevert("TaskBoard: start out of bounds");
        board.getTaskIdsInRange(5, 5);
    }

    // ──────────────────────────────────────────────
    //  End-to-end / integration
    // ──────────────────────────────────────────────

    function test_e2e_fullLifecycle() public {
        // CEO creates task
        vm.prank(ceo);
        uint256 taskId = board.createTask{value: 5 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);

        // Two contributors submit
        vm.prank(contributor1);
        board.submitDeliverable(taskId, contentHash1);
        vm.prank(contributor2);
        board.submitDeliverable(taskId, contentHash2);

        // CEO approves contributor2's submission
        vm.prank(ceo);
        board.approveSubmission(taskId, 1);

        // Verify state
        assertEq(board.pendingWithdrawals(contributor2), 5 ether);
        assertEq(board.pendingWithdrawals(contributor1), 0);
        assertEq(board.totalPaidOut(), 5 ether);

        // Contributor2 withdraws
        uint256 balBefore = contributor2.balance;
        vm.prank(contributor2);
        board.withdraw();
        assertEq(contributor2.balance, balBefore + 5 ether);

        // Contract balance should be zero
        assertEq(address(board).balance, 0);
    }

    function test_e2e_cancelRefundsAndNewTaskWorks() public {
        vm.prank(ceo);
        board.createTask{value: 2 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);

        uint256 ceoBalBefore = ceo.balance;
        vm.prank(ceo);
        board.cancelTask(0);
        assertEq(ceo.balance, ceoBalBefore + 2 ether);

        // CEO can create a new task after cancelling
        vm.prank(ceo);
        uint256 newId = board.createTask{value: 3 ether}(keccak256("new task"), 0, TaskBoard.ApprovalMode.CEO);
        assertEq(newId, 1);
    }

    function test_e2e_founderRotatesCeoMidFlow() public {
        vm.prank(ceo);
        board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);

        vm.prank(contributor1);
        board.submitDeliverable(0, contentHash1);

        // Founder rotates CEO
        address newCeo = makeAddr("newCeo");
        board.setCeo(newCeo);

        // Old CEO can no longer approve
        vm.prank(ceo);
        vm.expectRevert("TaskBoard: only CEO can approve this task");
        board.approveSubmission(0, 0);

        // New CEO can approve
        vm.prank(newCeo);
        board.approveSubmission(0, 0);

        (, , , , TaskBoard.TaskStatus status, , address winner,) = board.getTask(0);
        assertEq(uint8(status), uint8(TaskBoard.TaskStatus.Completed));
        assertEq(winner, contributor1);
    }

    // ──────────────────────────────────────────────
    //  Fuzz tests
    // ──────────────────────────────────────────────

    function testFuzz_createTask_arbitraryReward(uint256 reward) public {
        reward = bound(reward, 1, 100 ether);
        vm.deal(ceo, reward);

        vm.prank(ceo);
        board.createTask{value: reward}(descHash, 0, TaskBoard.ApprovalMode.CEO);

        (, uint256 storedReward, , , , , ,) = board.getTask(0);
        assertEq(storedReward, reward);
        assertEq(address(board).balance, reward);
    }

    function testFuzz_createTask_futureDeadline(uint256 deadline) public {
        deadline = bound(deadline, block.timestamp + 1, type(uint128).max);

        vm.prank(ceo);
        board.createTask{value: 1 ether}(descHash, deadline, TaskBoard.ApprovalMode.CEO);

        (, , uint256 storedDeadline, , , , ,) = board.getTask(0);
        assertEq(storedDeadline, deadline);
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _createDefaultTask() internal returns (uint256) {
        vm.prank(ceo);
        return board.createTask{value: 1 ether}(descHash, 0, TaskBoard.ApprovalMode.CEO);
    }

    function _submitAndApprove(uint256 taskId) internal {
        vm.prank(contributor1);
        board.submitDeliverable(taskId, contentHash1);

        vm.prank(ceo);
        board.approveSubmission(taskId, 0);
    }
}
