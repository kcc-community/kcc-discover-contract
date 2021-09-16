// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract DappStore is AccessControl, Initializable {
    using SafeERC20 for IERC20;
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    uint public minMarginAmount;
    uint public curPrimaryCategoryIndex;
    uint public curSecondaryCategoryIndex;

    enum ProjectState {
        None,
        Pending,
        Succeeded,
        Defeated,
        Canceled
    }
    ProjectState constant defaultProjectState = ProjectState.Pending;

    struct ProjectInfo {
        RequiredProjectInfo requiredProjectInfo;
        OptionalProjectInfo optionalProjectInfo;
        uint8 status;
        uint curVersion;
        uint createTime;
        bool updateStatus;
    }

    struct RequiredProjectInfo {
        string title;
        uint primaryCategoryIndex;
        uint secondaryCategoryIndex;
        string shortIntroduction;
        string logoLink;
        string banner;
        string websiteLink;
        string contractAddresses;
        string email;
        uint marginAmount;
    }

    struct OptionalProjectInfo {
        string tokenSymbol;
        string tokenContractAddress;
        string tvlInterface;
        string detailDescription;
        string twitterLink;
        string telegramLink;
        string githubLink;
        string coinmarketcapLink;
        string coingeckoLink;
    }

    struct ChangedInfo {
        OptionalProjectInfo optionalProjectInfo;
        uint primaryCategory;
        uint secondaryCategory;
        string shortIntroduction;
        string logoLink;
        string banner;
        string websiteLink;
        uint addMarginAmount;
    }

    struct CommentInfo {
        uint8 score;
        string title;
        string review;
        uint timestamp;
    }

    mapping(string => bool) public existPrimaryCategories;
    mapping(string => bool) public existSecondaryCategories;
    mapping(uint => string) public primaryCategories;
    mapping(uint => string) public secondaryCategories;
    mapping(address => ProjectInfo) public projectInfos;
    mapping(address => mapping(uint => ChangedInfo)) public changedInfos;
    mapping(address => mapping(address => CommentInfo)) public commentInfos;
    mapping(bytes32 => mapping(address => uint8)) public isLikeCommentInfos;

    event UpdateMinMarginAmount(uint amount);
    event AddPrimaryCategory(uint index, string primaryCategory);
    event UpdatePrimaryCategory(uint index, string newPrimaryCategory);
    event AddSecondaryCategory(uint index, string secondaryCategory);
    event UpdateSecondaryCategory(uint index, string newSecondaryCategory);
    event SubmitProjectInfo(address projectAddress, ProjectInfo projectInfo);
    event VerifySubmitProjectInfo(address projectAddress, uint8 status);
    event UpdateProjectInfo(address projectAddress, uint version, ChangedInfo _changedInfo);
    event VerifyUpdateProjectInfo(address projectAddress, uint version, bool isUpdate);
    event SubmitCommentInfo(address projectAddress, address submitAddress, CommentInfo commentInfo);
    event IsLikeCommentInfo(address projectAddress, address reviewer, address isLikeAddress, uint8 isLike);
    event DeleteComment(address projectAddress, address reviewer);


    // ["DeFi", "Infrastructure", "Tools"]
    // ["Exchange", "NFT", "Game", "Earn", "Lending", "DAO", "Wallet", "Community", "Others"]
    function initialize(string[] memory _primaryCategories, string[] memory _secondaryCategories) public initializer {
        minMarginAmount = 10 ** 17;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(VERIFIER_ROLE, _msgSender());

        for (uint index; index < _primaryCategories.length; index++) {
            addPrimaryCategory(_primaryCategories[index]);
        }
        for (uint index; index < _secondaryCategories.length; index++) {
            addSecondaryCategory(_secondaryCategories[index]);
        }
    }

    function updateMinMarginAmount(uint amount) public onlyOwner {
        minMarginAmount = amount;

        emit UpdateMinMarginAmount(amount);
    }

    function addPrimaryCategory(string memory primaryCategory) public onlyVerifier {
        require(!existPrimaryCategories[primaryCategory], "DS: primaryCategory already exists");
        primaryCategories[curPrimaryCategoryIndex] = primaryCategory;
        existPrimaryCategories[primaryCategory] = true;
        uint index = curPrimaryCategoryIndex;
        curPrimaryCategoryIndex++;

        emit AddPrimaryCategory(index, primaryCategory);
    }

    function updatePrimaryCategory(uint index, string calldata primaryCategory, string calldata newPrimaryCategory) public onlyVerifier {
        require(existPrimaryCategories[primaryCategory], "DS: primaryCategory must in primaryCategories");
        bytes32 primaryCategoryHash = keccak256(abi.encodePacked(primaryCategory));
        require(primaryCategoryHash == keccak256(abi.encodePacked(primaryCategories[index])), "DS: primaryCategories[index] != primaryCategory");
        primaryCategories[index] = newPrimaryCategory;
        delete existPrimaryCategories[primaryCategory];
        existPrimaryCategories[newPrimaryCategory] = true;

        emit UpdatePrimaryCategory(index, newPrimaryCategory);
    }

    function addSecondaryCategory(string memory secondaryCategory) public onlyVerifier {
        require(!existSecondaryCategories[secondaryCategory], "DS: secondaryCategory already exists");
        secondaryCategories[curSecondaryCategoryIndex] = secondaryCategory;
        existSecondaryCategories[secondaryCategory] = true;
        uint index = curSecondaryCategoryIndex;
        curSecondaryCategoryIndex++;

        emit AddSecondaryCategory(index, secondaryCategory);
    }

    function updateSecondaryCategory(uint index, string calldata secondaryCategory, string calldata newSecondaryCategory) public onlyVerifier {
        require(existSecondaryCategories[secondaryCategory], "DS: secondaryCategory must in secondaryCategories");
        bytes32 secondaryCategoryHash = keccak256(abi.encodePacked(secondaryCategory));
        require(secondaryCategoryHash == keccak256(abi.encodePacked(secondaryCategories[index])), "DS: secondaryCategories[index] != secondaryCategory");
        secondaryCategories[index] = newSecondaryCategory;
        delete existSecondaryCategories[secondaryCategory];
        existSecondaryCategories[newSecondaryCategory] = true;

        emit UpdateSecondaryCategory(index, newSecondaryCategory);
    }
    // ["title", 0, 0, "shortIntroduction", "logoLink", "bannerLink","websiteLink", "0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2", "xx@gmail.com", "100000000000000000"]
    // ["", "", "", "", "", "", "", "", ""]
    function submitProjectInfo(RequiredProjectInfo calldata requiredProjectInfo, OptionalProjectInfo calldata optionalProjectInfo) public payable onlyCheckedCategory(requiredProjectInfo.primaryCategoryIndex, requiredProjectInfo.secondaryCategoryIndex) {
        uint8 status = projectInfos[msg.sender].status;
        require(status == uint8(ProjectState.None) || status == uint8(ProjectState.Defeated), "DS: only one submission is allowed for an account");
        require(msg.value == requiredProjectInfo.marginAmount, "DS: margin amount error");
        require(msg.value >= minMarginAmount, "DS: insufficient value amounts");
        require(bytes(requiredProjectInfo.title).length <= 30, "DS: title length must <= 30");
        require(bytes(requiredProjectInfo.shortIntroduction).length <= 50, "DS: shortIntroduction length must <= 50");

        ProjectInfo storage projectInfo = projectInfos[msg.sender];
        projectInfo.requiredProjectInfo = requiredProjectInfo;
        projectInfo.optionalProjectInfo = optionalProjectInfo;
        projectInfo.status = uint8(defaultProjectState);
        projectInfo.createTime = block.timestamp;

        emit SubmitProjectInfo(msg.sender, projectInfo);
    }

    function successSubmittedProjectInfo(address projectAddress) public onlyVerifier {
        require(projectInfos[projectAddress].status == uint8(ProjectState.Pending), "DS: invalid _status value");
        changeProjectState(projectAddress, ProjectState.Succeeded);
    }

    function defeatSubmittedProjectInfo(address payable projectAddress) public onlyVerifier {
        require(projectInfos[projectAddress].status == uint8(ProjectState.Pending), "DS: invalid _status value");
        projectAddress.transfer(projectInfos[projectAddress].requiredProjectInfo.marginAmount);
        changeProjectState(projectAddress, ProjectState.Defeated);
    }

    function cancelledProject(address payable projectAddress) public onlyVerifier {
        require(projectInfos[projectAddress].status == uint8(ProjectState.Succeeded), "DS: invalid _status value");
        changeProjectState(projectAddress, ProjectState.Canceled);
    }

    function changeProjectState(address projectAddress, ProjectState _status) internal {
        projectInfos[projectAddress].status = uint8(_status);
        emit VerifySubmitProjectInfo(projectAddress, uint8(_status));
    }

    // [["", "", "", "", "", "", "", "", ""], 1, 1, "shortIntroduction", "logoLink", "bannerLink","websiteLink", "0"]
    function updateProjectInfo(address projectAddress, ChangedInfo calldata _changedInfo) public payable onlyPassedProject(projectAddress) onlyCheckedCategory(_changedInfo.primaryCategory, _changedInfo.secondaryCategory) {
        require(!projectInfos[projectAddress].updateStatus, "DS: updateStatus must be false");
        require(msg.sender == projectAddress, "DS: projectAddress must be equal to msg.sender");
        require(msg.value == _changedInfo.addMarginAmount, "DS: msg.value not equal to addMarginAmount");
        require(_changedInfo.addMarginAmount + projectInfos[projectAddress].requiredProjectInfo.marginAmount >= minMarginAmount, "DS: insufficient margin amount");
        require(bytes(_changedInfo.shortIntroduction).length <= 50, "DS: shortIntroduction length must <= 50");

        uint version = ++projectInfos[projectAddress].curVersion;
        changedInfos[projectAddress][version] = _changedInfo;
        projectInfos[projectAddress].updateStatus = true;

        emit UpdateProjectInfo(projectAddress, version, _changedInfo);
    }

    function successUpdatedProjectInfo(address projectAddress) public onlyVerifier onlyPassedProject(projectAddress) onlyPendingUpdate(projectAddress) {
        uint version = projectInfos[projectAddress].curVersion;
        uint newMarginAmount = projectInfos[projectAddress].requiredProjectInfo.marginAmount + changedInfos[projectAddress][version].addMarginAmount;
        projectInfos[projectAddress].requiredProjectInfo.marginAmount = newMarginAmount;
        changeUpdatedProjectState(projectAddress, version, true);
    }

    function defeatUpdatedProjectInfo(address payable projectAddress) public onlyVerifier onlyPassedProject(projectAddress) onlyPendingUpdate(projectAddress) {
        uint version = projectInfos[projectAddress].curVersion;
        if (changedInfos[projectAddress][version].addMarginAmount > 0) {
            projectAddress.transfer(changedInfos[projectAddress][version].addMarginAmount);
        }
        changeUpdatedProjectState(projectAddress, version, false);
    }

    function changeUpdatedProjectState(address projectAddress, uint version, bool isUpdate) internal {
        projectInfos[projectAddress].updateStatus = false;
        emit VerifyUpdateProjectInfo(projectAddress, version, isUpdate);
    }

    function submitCommentInfo(address projectAddress, uint8 score, string calldata title, string calldata review) public onlyPassedProject(projectAddress) {
        require(commentInfos[projectAddress][msg.sender].score == 0, "DS: one project can be reviewed at the same address");
        require(score >= 5 && score <= 50, "DS: score must between 5 and 50");
        uint title_length = bytes(title).length;
        require(title_length > 0 && title_length <= 30, "DS: title length must between 1 and 30");

        CommentInfo memory commentInfo = CommentInfo(score, title, review, block.timestamp);
        commentInfos[projectAddress][msg.sender] = commentInfo;

        emit SubmitCommentInfo(projectAddress, msg.sender, commentInfo);
    }

    function deleteComment(address projectAddress) public onlyPassedProject(projectAddress) {
        require(commentInfos[projectAddress][msg.sender].score > 0, "DS: review must exist");
        delete commentInfos[projectAddress][msg.sender];

        emit DeleteComment(projectAddress, msg.sender);
    }

    // isLike=0 => default, isLike=1 => like, isLike=2 => dislike
    function isLikeCommentInfo(address projectAddress, address reviewer, uint8 isLike) public onlyPassedProject(projectAddress) {
        require(isLike >= 0 && isLike <= 2, "DS: isLike must between 0 and 2");
        require(commentInfos[projectAddress][reviewer].score > 0, "DS: review must exist");
        bytes32 commentHash = keccak256(abi.encodePacked(projectAddress, reviewer));
        isLikeCommentInfos[commentHash][msg.sender] = isLike;

        emit IsLikeCommentInfo(projectAddress, reviewer, msg.sender, isLike);
    }

    function withdrawMargin(address payable to, uint amount) public onlyOwner {
        require(address(this).balance >= amount, "DS: insufficient contract balance");
        to.transfer(amount);
    }

    function withdrawKRC20Token(address tokenAddress, address to, uint amount) public onlyOwner {
        require(IERC20(tokenAddress).balanceOf(address(this)) >= amount, "DS: insufficient contract balance");
        IERC20(tokenAddress).safeTransfer(to, amount);
    }

    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "DS: caller is not the owner");
        _;
    }

    modifier onlyVerifier() {
        require(hasRole(VERIFIER_ROLE, _msgSender()), "DS: caller is not the verifier");
        _;
    }

    modifier onlyCheckedCategory(uint primaryCategoryIndex, uint secondaryCategoryIndex) {
        string memory primaryCategory = primaryCategories[primaryCategoryIndex];
        string memory secondaryCategory = secondaryCategories[secondaryCategoryIndex];
        require(existPrimaryCategories[primaryCategory], "DS: primaryCategory error");
        require(existSecondaryCategories[secondaryCategory], "DS: secondaryCategory error");
        _;
    }

    modifier onlyPassedProject(address projectAddress) {
        require(projectInfos[projectAddress].status == uint8(ProjectState.Succeeded), "DS: project must have passed");
        _;
    }

    modifier onlyPendingUpdate(address projectAddress) {
        require(projectInfos[projectAddress].updateStatus, "DS: no updated info to review");
        _;
    }
}
