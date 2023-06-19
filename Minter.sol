// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "hardhat/console.sol";

interface IMintable {
    function safeMint(address to, uint256 tokenId) external;
}

// Minter can manage multiple ERC721 token contracts, such as character, weapon and so on.
// Each ERC721 contract can have multiple token types.
// Each token type can have multiple stages.
contract Minter is Ownable, ReentrancyGuard {
    struct Stage {
        uint256 mintLimit; // limit for each address, max = totalLimit
        uint256 totalLimit;
        uint256 tokenPrice; // zero means free
        uint256 startingTime; // zero means no starting time limit
        uint256 endingTime; // zero means no ending time limit
        bool useWhiteList;
    }

    using Counters for Counters.Counter;

    Counters.Counter private _globalTokenTypeIdCounter;
    mapping(address => Counters.Counter) private _tokenTypeIdCounter; // ERC721 contract address => current token type count
    mapping(address => mapping(uint256 => uint256)) private _tokenTypeIdMap; // local token type => global token type
    mapping(address => mapping(uint256 => bool)) _addressToTokenTypeMap;

    Counters.Counter private _globalStageIdCounter;
    mapping(uint256 => Counters.Counter) private _stageIdCounter; // global token type id => current stage count
    mapping(uint256 => mapping(uint256 => uint256)) private _stageIdMap; // global token type id => (local stage id => global stage id))
    mapping(uint256 => mapping(uint256 => bool)) private _tokenTypeToStageMap;

    // Each stage has current minted count, total limit, price and stage ending time
    mapping(uint256 => Counters.Counter) private _stageTokenCountMap; // global stage id => minted count
    mapping(uint256 => Stage) private _stageStructMap;

    // mapping(uint256 => uint256) private _stageMintLimitMap;
    // mapping(uint256 => uint256) private _stageTotalLimitMap;
    // mapping(uint256 => uint256) private _stageTokenPriceMap;
    // mapping(uint256 => uint256) private _stageStartingTimeMap; // start time is zero means no starting limit
    // mapping(uint256 => uint256) private _stageEndingTimeMap; // ending time is zero means no ending limit
    // mapping(uint256 => bool) private _stageUseWhiteListMap;

    // global stage id => (user address => bool)
    mapping(uint256 => mapping(address => bool)) private _stageUserWhiteListMap; // global stage id => (user address => is on the list)
    mapping(uint256 => mapping(address => uint256))
        private _stageUserBalanceMap; // global stage id => (user address => minted count)

    // contract address => (token type id => (stage id => index))
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        private _tokenIndexMap; // means the token id start index in its contract address

    event TokenTypeAdded(
        address tokenAddress,
        uint256 tokenTypeId,
        uint256 globalTokenTypeId
    );
    event TokenStageAdded(
        address tokenAddress,
        uint256 tokenTypeId,
        uint256 stageId,
        uint256 globalStageId
    );

    constructor() {}

    // ----------external functions starts here----------

    /// @dev add a token type in the specified ERC721 contract
    function addTokenType(
        address tokenAddress // ERC721 contract address
    ) external onlyOwner {
        uint256 tokenTypeId = _tokenTypeIdCounter[tokenAddress].current();
        uint256 globalTokenTypeId = _globalTokenTypeIdCounter.current();

        _tokenTypeIdMap[tokenAddress][tokenTypeId] = globalTokenTypeId;
        _addressToTokenTypeMap[tokenAddress][tokenTypeId] = true;

        _tokenTypeIdCounter[tokenAddress].increment();
        _globalTokenTypeIdCounter.increment();

        emit TokenTypeAdded(tokenAddress, tokenTypeId, globalTokenTypeId);
    }

    function getTokenTypeCount(
        address tokenAddress
    ) external view returns (uint256) {
        return _tokenTypeIdCounter[tokenAddress].current();
    }

    function addTokenStage(
        address tokenAddress, // ERC721 contract address
        uint256 tokenTypeId,
        Stage memory stage
    ) external onlyOwner {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] = true,
            "addTokenStage: token type not added"
        );
        require(
            stage.totalLimit > 0,
            "addTokenStage: token limit must be greater than zero"
        );

        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        uint256 stageId = _stageIdCounter[globalTokenTypeId].current();
        uint256 globalStageId = _globalStageIdCounter.current();

        _stageIdCounter[globalTokenTypeId].increment();
        _globalStageIdCounter.increment();

        _stageIdMap[globalTokenTypeId][stageId] = globalStageId;
        _tokenTypeToStageMap[globalTokenTypeId][stageId] = true;

        _stageStructMap[globalStageId] = stage;

        // _stageMintLimitMap[globalStageId] = mintLimit;
        // _stageTotalLimitMap[globalStageId] = totalLimit;
        // _stageTokenPriceMap[globalStageId] = tokenPrice;
        // _stageStartingTimeMap[globalStageId] = startingTime;
        // _stageEndingTimeMap[globalStageId] = endingTime;
        // _stageUseWhiteListMap[globalStageId] = useWhiteList;

        // contract address => (token type id => (stage id => index))
        if (tokenTypeId == 0) {
            if (stageId == 0) {
                _tokenIndexMap[tokenAddress][tokenTypeId][stageId] = 0;
            } else {
                uint256 lastGlobalStageId = _stageIdMap[globalTokenTypeId][
                    stageId - 1
                ];
                _tokenIndexMap[tokenAddress][tokenTypeId][stageId] =
                    _tokenIndexMap[tokenAddress][tokenTypeId][stageId - 1] +
                    _stageStructMap[lastGlobalStageId].totalLimit;
            }
        } else {
            if (stageId == 0) {
                uint256 lastGlobalTokenTypeId = _tokenTypeIdMap[tokenAddress][
                    tokenTypeId - 1
                ];
                uint256 lastStageId = _stageIdCounter[lastGlobalTokenTypeId]
                    .current() - 1;
                uint256 lastGlobalStageId = _stageIdMap[lastGlobalTokenTypeId][
                    lastStageId
                ];
                _tokenIndexMap[tokenAddress][tokenTypeId][stageId] =
                    _tokenIndexMap[tokenAddress][tokenTypeId - 1][lastStageId] +
                    _stageStructMap[lastGlobalStageId].totalLimit;
            } else {
                uint256 lastGlobalStageId = _stageIdMap[globalTokenTypeId][
                    stageId - 1
                ];
                _tokenIndexMap[tokenAddress][tokenTypeId][stageId] =
                    _tokenIndexMap[tokenAddress][tokenTypeId][stageId - 1] +
                    _stageStructMap[lastGlobalStageId].totalLimit;
            }
        }

        emit TokenStageAdded(tokenAddress, tokenTypeId, stageId, globalStageId);
    }

    /// @dev getTokenStageCount get how many stages this token type has
    function getTokenStageCount(
        address tokenAddress,
        uint256 tokenTypeId
    ) external view returns (uint256) {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "getTokenStageCount: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];

        return _stageIdCounter[globalTokenTypeId].current();
    }

    // ==================================================================================
    function getStageProperties(
        address tokenAddress,
        uint256 tokenTypeId,
        uint256 stageId
    )
        external
        view
        returns (
            // returns (uint256, uint256, uint256, uint256, uint256, bool)
            Stage memory
        )
    {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "getStageProperties: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "getStageProperties: stage not added"
        );
        uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

        return _stageStructMap[globalStageId];
    }

    //=============not supported by zkEVM======================================
    // function getTokenAllStages(
    //     address tokenAddress,
    //     uint256 tokenTypeId
    // ) external view returns (Stage[] memory) {
    //     require(
    //         _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
    //         "getTokenAllStages: token type not added"
    //     );
    //     uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];

    //     uint256 count = _stageIdCounter[globalTokenTypeId].current();
    //     Stage[] memory stages = new Stage[](count);

    //     if (count == 0) {
    //         return stages;
    //     }

    //     for (uint256 i = 0; i < count; i++){
    //         require(
    //             _tokenTypeToStageMap[globalTokenTypeId][i] == true,
    //             "getTokenAllStages: fatal! stage not added"
    //         );
    //         uint256 globalStageId = _stageIdMap[globalTokenTypeId][i];
    //         stages[i] = _stageStructMap[globalStageId];
    //     }
    //     return stages;
    // }

    // // =====================try returning multiple values=================================
    // function getStageMintLimit(
    //     address tokenAddress,
    //     uint256 tokenTypeId,
    //     uint256 stageId
    // ) external view returns (uint256) {
    //     require(
    //         _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
    //         "getStageMintLimit: token type not added"
    //     );
    //     uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
    //     require(
    //         _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
    //         "getStageMintLimit: stage not added"
    //     );
    //     uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

    //     return _stageStructMap[globalStageId].mintLimit;
    // }

    // function getStageTotalLimit(
    //     address tokenAddress,
    //     uint256 tokenTypeId,
    //     uint256 stageId
    // ) external view returns (uint256) {
    //     require(
    //         _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
    //         "getStageTotalLimit: token type not added"
    //     );
    //     uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
    //     require(
    //         _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
    //         "getStageTotalLimit: stage not added"
    //     );
    //     uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

    //     return _stageStructMap[globalStageId].totalLimit;
    // }

    // /// @dev getStageTokenPrice returns the token price
    // function getStageTokenPrice(
    //     address tokenAddress,
    //     uint256 tokenTypeId,
    //     uint256 stageId
    // ) external view returns (uint256) {
    //     require(
    //         _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
    //         "getStageTokenPrice: token type not added"
    //     );
    //     uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
    //     require(
    //         _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
    //         "getStageTokenPrice: stage not added"
    //     );
    //     uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];
    //     return _stageStructMap[globalStageId].tokenPrice;
    // }

    // function getStageStartingTime(
    //     address tokenAddress,
    //     uint256 tokenTypeId,
    //     uint256 stageId
    // ) external view returns (uint256) {
    //     require(
    //         _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
    //         "getStageStartingTime: token type not added"
    //     );
    //     uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
    //     require(
    //         _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
    //         "getStageStartingTime: stage not added"
    //     );
    //     uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

    //     return _stageStructMap[globalStageId].startingTime;
    // }

    // function getStageEndingTime(
    //     address tokenAddress,
    //     uint256 tokenTypeId,
    //     uint256 stageId
    // ) external view returns (uint256) {
    //     require(
    //         _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
    //         "getStageEndingTime: token type not added"
    //     );
    //     uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
    //     require(
    //         _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
    //         "getStageEndingTime: stage not added"
    //     );
    //     uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

    //     return _stageStructMap[globalStageId].endingTime;
    // }

    // /// @dev get if the stage uses whitelist or not
    // function getStageUseWhiteList(
    //     address tokenAddress,
    //     uint256 tokenTypeId,
    //     uint256 stageId
    // ) external view returns (bool) {
    //     require(
    //         _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
    //         "getStageUseWhiteList: token type not added"
    //     );
    //     uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
    //     require(
    //         _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
    //         "getStageUseWhiteList: stage not added"
    //     );
    //     uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

    //     return _stageStructMap[globalStageId].useWhiteList;
    // }

    //=========================================================================================

    function getStageStartIndex(
        address tokenAddress,
        uint256 tokenTypeId,
        uint256 stageId
    ) external view returns (uint256) {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "getStageStartIndex: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "getStageStartIndex: stage not added"
        );

        return _tokenIndexMap[tokenAddress][tokenTypeId][stageId];
    }

    // --------- whitelist start ----------
    function addUsersToWhiteList(
        address tokenAddress, // ERC721 contract address
        uint256 tokenTypeId,
        uint256 stageId,
        address[] memory users
    ) external onlyOwner {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "addUsersToWhiteList: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "addUsersToWhiteList: stage not added"
        );
        uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];
        require(
            _stageStructMap[globalStageId].useWhiteList == true,
            "addUsersToWhiteList: stage not use whitelist"
        );

        for (uint256 i = 0; i < users.length; i++) {
            _stageUserWhiteListMap[globalStageId][users[i]] = true;
        }
    }

    function getUserIfWhiteListed(
        address tokenAddress, // ERC721 contract address
        uint256 tokenTypeId,
        uint256 stageId,
        address user
    ) external view returns (bool) {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "getUserIfWhiteListed: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "getUserIfWhiteListed: stage not added"
        );
        uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];
        require(
            _stageStructMap[globalStageId].useWhiteList == true,
            "getUserIfWhiteListed: stage not use whitelist"
        );

        return _stageUserWhiteListMap[globalStageId][user];
    }

    // --------- whitelist end ----------

    /// @dev mintNow checks mint time inside
    function mintNow(
        address to,
        address tokenAddress,
        uint256 tokenTypeId,
        uint256 stageId,
        uint256 count
    ) external payable nonReentrant {
        require(to != address(0), "mintNow: zero address");
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "mintNow: token type not added"
        );

        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "mintNow: stage not added"
        );
        require(count > 0, "mintNow: batch too small");

        uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];
        // check if user is whitelisted
        if (_stageStructMap[globalStageId].useWhiteList == true) {
            require(
                _stageUserWhiteListMap[globalStageId][to] == true,
                "mintNow: user address is not whitelisted"
            );
        }
        // check if mint limit is exceeded
        require(
            _stageUserBalanceMap[globalStageId][to] + count <=
                _stageStructMap[globalStageId].mintLimit,
            "mintNow: stage mint limit exceeded"
        );

        // check mint time
        if (_stageStructMap[globalStageId].startingTime > 0) {
            require(
                block.timestamp >= _stageStructMap[globalStageId].startingTime,
                "mintNow: stage not started"
            );
        }
        if (_stageStructMap[globalStageId].endingTime > 0) {
            require(
                block.timestamp <= _stageStructMap[globalStageId].endingTime,
                "mintNow: stage ended"
            );
        }

        // check remained token count
        require(
            _stageTokenCountMap[globalStageId].current() + count <=
                _stageStructMap[globalStageId].totalLimit,
            "mintNow: stage total limit exceeded"
        );
        // check payed price
        require(
            msg.value >= _stageStructMap[globalStageId].tokenPrice * count,
            "mintNow: not enough ETH sent"
        );

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _tokenIndexMap[tokenAddress][tokenTypeId][
                stageId
            ] + _stageTokenCountMap[globalStageId].current();
            _stageTokenCountMap[globalStageId].increment();

            IMintable(tokenAddress).safeMint(to, tokenId);

            _stageUserBalanceMap[globalStageId][to]++;
        }
    }

    /// @dev get user's token amount at a specified stage
    function getStageUserBalance(
        address tokenAddress, // ERC721 contract address
        uint256 tokenTypeId,
        uint256 stageId,
        address user
    ) external view returns (uint256) {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "getStageUserBalance: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "getStageUserBalance: stage not added"
        );
        uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

        return _stageUserBalanceMap[globalStageId][user];
    }

    /// @dev get how many tokens this user still can mint at a specified stage
    function getStageUserAvailableCount(
        address tokenAddress, // ERC721 contract address
        uint256 tokenTypeId,
        uint256 stageId,
        address user
    ) public view returns (uint256) {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "getStageUserAvailableCount: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "getStageUserAvailableCount: stage not added"
        );
        uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];
        require(
            _stageUserBalanceMap[globalStageId][user] <=
                _stageStructMap[globalStageId].mintLimit,
            "getStageUserAvailableCount: fatal! stage user balance greater than limit"
        );

        if (_stageStructMap[globalStageId].useWhiteList) {
            if (_stageUserWhiteListMap[globalStageId][user] == false) {
                return 0;
            }
        }

        return
            _stageStructMap[globalStageId].mintLimit -
            _stageUserBalanceMap[globalStageId][user];
    }

    /// @dev get this user has available amount or not at a specified stage
    function getStageUserAvailable(
        address tokenAddress, // ERC721 contract address
        uint256 tokenTypeId,
        uint256 stageId,
        address user
    ) external view returns (bool) {
        return
            getStageUserAvailableCount(
                tokenAddress,
                tokenTypeId,
                stageId,
                user
            ) > 0;
    }

    /// @dev getStageMintedCount returns the minted token amount of a specified stage
    function getStageMintedCount(
        address tokenAddress, // ERC721 contract address
        uint256 tokenTypeId,
        uint256 stageId
    ) external view returns (uint256) {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "getMintedTokenCount: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "getMintedTokenCount: stage not added"
        );
        uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

        return _stageTokenCountMap[globalStageId].current();
    }

    /// @dev getStageAvailableCount returns the available token amount of a specified stage
    function getStageAvailableCount(
        address tokenAddress, // ERC721 contract address
        uint256 tokenTypeId,
        uint256 stageId
    ) external view returns (uint256) {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "getAvailableTokenCount: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "getAvailableTokenCount: stage not added"
        );
        uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

        return
            _stageStructMap[globalStageId].totalLimit -
            _stageTokenCountMap[globalStageId].current();
    }

    /// @dev withdraw can withdraw the eth in this contract address
    function withdraw() external payable onlyOwner {
        uint balance = address(this).balance;
        require(balance > 0, "No ether left to withdraw");

        (bool success, ) = (msg.sender).call{value: balance}("");
        require(success, "Transfer failed.");
    }

    /// @dev for testing purpose only!!!
    function updateTokenStage(
        address tokenAddress, // ERC721 contract address
        uint256 tokenTypeId,
        uint256 stageId,
        Stage memory newStage
    ) external onlyOwner {
        require(
            _addressToTokenTypeMap[tokenAddress][tokenTypeId] == true,
            "updateTokenStage: token type not added"
        );
        uint256 globalTokenTypeId = _tokenTypeIdMap[tokenAddress][tokenTypeId];
        require(
            _tokenTypeToStageMap[globalTokenTypeId][stageId] == true,
            "updateTokenStage: stage not added"
        );
        uint256 globalStageId = _stageIdMap[globalTokenTypeId][stageId];

        require(
            _stageStructMap[globalStageId].totalLimit >= newStage.totalLimit,
            "updateTokenStage: total limit cannot be greater than previous amount"
        );

        _stageStructMap[globalStageId] = newStage;
    }
}
