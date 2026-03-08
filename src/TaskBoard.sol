// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TaskBoard
/// @notice Founder/CEO-managed task board funded in native ETH.
///         The CEO is an AI agent that creates and funds tasks, contributors
///         submit deliverables, and the designated approver (AI CEO or founder)
///         selects a winner. Winner payouts use the pull-payment pattern via withdraw().
contract TaskBoard is ReentrancyGuard {
    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────

    enum ApprovalMode {
        CEO,
        Founder
    }

    enum TaskStatus {
        Open,
        Completed,
        Cancelled
    }

    struct Submission {
        address contributor;
        bytes32 contentHash; // IPFS CID hash / keccak256 of deliverable reference
        uint256 submittedAt;
    }

    struct Task {
        bytes32 descriptionHash; // keccak256 of task description / offchain reference
        uint256 reward; // ETH amount currently held in escrow for this task
        uint256 deadline; // Unix timestamp — 0 means no deadline
        ApprovalMode approvalMode;
        TaskStatus status;
        uint256 createdAt;
        address winner; // approved winner
        uint256 submissionCount;
    }

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    address public immutable founder;
    address public ceo;

    Task[] public tasks;

    // taskId => submissionIndex => Submission
    mapping(uint256 => mapping(uint256 => Submission)) public submissions;

    // Tracks rewards allocated to contributors but not yet withdrawn
    mapping(address => uint256) public pendingWithdrawals;

    uint256 public totalTasksCreated;
    uint256 public totalPaidOut;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event TaskCreated(
        uint256 indexed taskId,
        bytes32 descriptionHash,
        uint256 reward,
        uint256 deadline,
        ApprovalMode approvalMode
    );

    event SubmissionReceived(
        uint256 indexed taskId,
        uint256 indexed submissionIndex,
        address indexed contributor,
        bytes32 contentHash
    );

    event SubmissionApproved(
        uint256 indexed taskId,
        uint256 indexed submissionIndex,
        address indexed winner,
        uint256 amount
    );

    event TaskCancelled(
        uint256 indexed taskId,
        address indexed cancelledBy,
        address indexed refundedTo,
        uint256 amount
    );

    event TaskStatusChanged(
        uint256 indexed taskId,
        TaskStatus oldStatus,
        TaskStatus newStatus
    );

    event Withdrawal(address indexed payee, uint256 amount);

    event CeoUpdated(address indexed oldCeo, address indexed newCeo);

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    modifier onlyFounder() {
        require(msg.sender == founder, "TaskBoard: caller is not the founder");
        _;
    }

    modifier onlyCeo() {
        require(msg.sender == ceo, "TaskBoard: caller is not the CEO");
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    /// @param _ceo Initial CEO wallet
    constructor(address _ceo) {
        require(_ceo != address(0), "TaskBoard: CEO cannot be zero address");
        founder = msg.sender;
        ceo = _ceo;
    }

    // ──────────────────────────────────────────────
    //  CEO Actions
    // ──────────────────────────────────────────────

    /// @notice CEO creates a new task and funds it with ETH.
    /// @param descriptionHash Hash of the task description
    /// @param deadline Unix timestamp after which new submissions are blocked. 0 = no deadline.
    /// @param approvalMode Who approves submissions: 0 = CEO, 1 = Founder
    /// @return taskId ID of the newly created task
    function createTask(
        bytes32 descriptionHash,
        uint256 deadline,
        ApprovalMode approvalMode
    ) external payable onlyCeo nonReentrant returns (uint256 taskId) {
        require(
            descriptionHash != bytes32(0),
            "TaskBoard: empty description hash"
        );
        require(msg.value > 0, "TaskBoard: reward must be greater than zero");
        require(
            deadline == 0 || deadline > block.timestamp,
            "TaskBoard: deadline must be in the future"
        );

        taskId = tasks.length;

        tasks.push(
            Task({
                descriptionHash: descriptionHash,
                reward: msg.value,
                deadline: deadline,
                approvalMode: approvalMode,
                status: TaskStatus.Open,
                createdAt: block.timestamp,
                winner: address(0),
                submissionCount: 0
            })
        );

        totalTasksCreated++;

        emit TaskCreated(
            taskId,
            descriptionHash,
            msg.value,
            deadline,
            approvalMode
        );
    }

    // ──────────────────────────────────────────────
    //  Contributor Actions
    // ──────────────────────────────────────────────

    /// @notice CEO submits a deliverable on behalf of a contributor.
    /// @param taskId The task to submit to
    /// @param contentHash Hash/reference of the deliverable
    /// @param contributor The contributor's address to credit
    /// @return submissionIndex Index of the new submission
    function submitOnBehalfOf(
        uint256 taskId,
        bytes32 contentHash,
        address contributor
    ) external onlyCeo returns (uint256 submissionIndex) {
        require(contributor != address(0), "TaskBoard: contributor cannot be zero address");
        return _submitDeliverable(taskId, contentHash, contributor);
    }

    /// @notice Submit a deliverable for an open task.
    /// @param taskId The task to submit to
    /// @param contentHash Hash/reference of the deliverable
    /// @return submissionIndex Index of the new submission
    function submitDeliverable(
        uint256 taskId,
        bytes32 contentHash
    ) external returns (uint256 submissionIndex) {
        return _submitDeliverable(taskId, contentHash, msg.sender);
    }

    // ──────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────

    function _submitDeliverable(
        uint256 taskId,
        bytes32 contentHash,
        address contributor
    ) internal returns (uint256 submissionIndex) {
        require(taskId < tasks.length, "TaskBoard: task does not exist");
        require(contentHash != bytes32(0), "TaskBoard: empty content hash");

        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.Open, "TaskBoard: task not open");
        require(
            t.deadline == 0 || block.timestamp <= t.deadline,
            "TaskBoard: task expired"
        );

        submissionIndex = t.submissionCount;

        submissions[taskId][submissionIndex] = Submission({
            contributor: contributor,
            contentHash: contentHash,
            submittedAt: block.timestamp
        });

        t.submissionCount++;

        emit SubmissionReceived(
            taskId,
            submissionIndex,
            contributor,
            contentHash
        );
    }

    // ──────────────────────────────────────────────
    //  Approval
    // ──────────────────────────────────────────────

    /// @notice Approve a submission and allocate funds to the contributor.
    /// @dev Uses the pull-payment pattern. Contributors must call withdraw() to claim funds.
    ///      Approval is allowed even after the submission deadline, as long as the task is still open.
    /// @param taskId The task ID
    /// @param submissionIndex Submission index to approve
    function approveSubmission(
        uint256 taskId,
        uint256 submissionIndex
    ) external nonReentrant {
        require(taskId < tasks.length, "TaskBoard: task does not exist");

        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.Open, "TaskBoard: task not open");
        require(
            submissionIndex < t.submissionCount,
            "TaskBoard: submission does not exist"
        );

        if (t.approvalMode == ApprovalMode.CEO) {
            require(
                msg.sender == ceo,
                "TaskBoard: only CEO can approve this task"
            );
        } else {
            require(
                msg.sender == founder,
                "TaskBoard: only founder can approve this task"
            );
        }

        Submission storage s = submissions[taskId][submissionIndex];

        uint256 reward = t.reward;
        TaskStatus oldStatus = t.status;

        t.status = TaskStatus.Completed;
        t.winner = s.contributor;
        t.reward = 0;

        totalPaidOut += reward;
        pendingWithdrawals[s.contributor] += reward;

        emit TaskStatusChanged(taskId, oldStatus, TaskStatus.Completed);
        emit SubmissionApproved(taskId, submissionIndex, s.contributor, reward);
    }

    // ──────────────────────────────────────────────
    //  Cancel / Refund
    // ──────────────────────────────────────────────

    /// @notice Cancel an open task and refund its escrow to the current CEO.
    /// @dev Only the founder or CEO can cancel. Public cancellation is not allowed.
    /// @param taskId The task to cancel
    function cancelTask(uint256 taskId) external nonReentrant {
        require(taskId < tasks.length, "TaskBoard: task does not exist");
        require(
            msg.sender == founder || msg.sender == ceo,
            "TaskBoard: unauthorized cancel"
        );

        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.Open, "TaskBoard: task not open");

        uint256 reward = t.reward;
        TaskStatus oldStatus = t.status;

        t.status = TaskStatus.Cancelled;
        t.reward = 0;

        (bool success, ) = payable(ceo).call{value: reward}("");
        require(success, "TaskBoard: refund failed");

        emit TaskStatusChanged(taskId, oldStatus, TaskStatus.Cancelled);
        emit TaskCancelled(taskId, msg.sender, ceo, reward);
    }

    // ──────────────────────────────────────────────
    //  Withdrawal
    // ──────────────────────────────────────────────

    /// @notice Allows contributors to withdraw their accumulated rewards.
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "TaskBoard: no funds to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "TaskBoard: withdrawal failed");

        emit Withdrawal(msg.sender, amount);
    }

    // ──────────────────────────────────────────────
    //  Founder Admin
    // ──────────────────────────────────────────────

    /// @notice Founder can rotate the CEO address.
    function setCeo(address newCeo) external onlyFounder {
        require(newCeo != address(0), "TaskBoard: CEO cannot be zero address");
        emit CeoUpdated(ceo, newCeo);
        ceo = newCeo;
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    function taskCount() external view returns (uint256) {
        return tasks.length;
    }

    function getTask(
        uint256 taskId
    )
        external
        view
        returns (
            bytes32 descriptionHash,
            uint256 reward,
            uint256 deadline,
            ApprovalMode approvalMode,
            TaskStatus status,
            uint256 createdAt,
            address winner,
            uint256 submissionCount
        )
    {
        require(taskId < tasks.length, "TaskBoard: task does not exist");
        Task storage t = tasks[taskId];

        return (
            t.descriptionHash,
            t.reward,
            t.deadline,
            t.approvalMode,
            t.status,
            t.createdAt,
            t.winner,
            t.submissionCount
        );
    }

    function getSubmission(
        uint256 taskId,
        uint256 submissionIndex
    )
        external
        view
        returns (address contributor, bytes32 contentHash, uint256 submittedAt)
    {
        require(taskId < tasks.length, "TaskBoard: task does not exist");

        Task storage t = tasks[taskId];
        require(
            submissionIndex < t.submissionCount,
            "TaskBoard: submission does not exist"
        );

        Submission storage s = submissions[taskId][submissionIndex];
        return (s.contributor, s.contentHash, s.submittedAt);
    }

    /// @notice Returns task IDs from [start, end) for simple pagination.
    /// @dev If end > tasks.length, it is clamped to tasks.length.
    function getTaskIdsInRange(
        uint256 start,
        uint256 end
    ) external view returns (uint256[] memory ids) {
        require(start <= end, "TaskBoard: invalid range");

        uint256 len = tasks.length;
        if (end > len) {
            end = len;
        }

        require(start < len || start == end, "TaskBoard: start out of bounds");

        uint256 count = end - start;
        ids = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            ids[i] = start + i;
        }
    }
}
