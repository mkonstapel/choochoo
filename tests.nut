class RunTests extends Task {
    constructor() {
        Task.constructor(null, [BuildAllCrossings(), Halt()]);
    }
}

class BuildTestNetwork extends Task {
    network = null;

    constructor() {
        Task.constructor(parentTask);
        
        this.network = Network(AIRailTypeList().Begin(), IsRightHandTraffic(), 3, 0, 256);
    }
    
    function Run() {
        local crossingTile1, crossingTile2;

        if (!subtasks) {
            crossingTile1 = AIMap.GetTileIndex(128, 128);
            crossingTile2 = AIMap.GetTileIndex(128, 192);
            SetConstructionSign(crossingTile1, this);
            AIRail.SetCurrentRailType(network.railType);
            subtasks = [
                LevelTerrain(this, crossingTile1, Rotation.ROT_0, [1, 1], [Crossing.WIDTH-2, Crossing.WIDTH-2], false),
                BuildCrossing(this, crossingTile1, network),
                BuildCrossing(this, crossingTile2, network),
                ConnectCrossing(this, crossingTile1, Direction.SE, crossingTile2, Direction.NW, network)
            ];
        }
        
        RunSubtasks();
    }
    
    function _tostring() {
        return "BuildTestNetwork";
    }
}

class BuildAllCrossings extends Task {
    network = null;

    constructor() {
        Task.constructor(parentTask);
        this.network = Network(AIRailTypeList().Begin(), IsRightHandTraffic(), 3, 0, 256);
    }

    function Run() {
        if (!subtasks) {
            AIRail.SetCurrentRailType(network.railType);
            local allDirections = [Direction.NE, Direction.SE, Direction.SW, Direction.NW];
            subtasks = [];

            local col = 0;
            for (local numRemoved = 1; numRemoved <= 4; numRemoved++) {
                for (local rot = 0; rot < 4; rot++) {
                    local tile = AIMap.GetTileIndex(64 + col * 8, 64);
                    local exitsToRemove = [];
                    for (local i = 0; i < numRemoved; i++) {
                        exitsToRemove.append(allDirections[(rot + i) % 4]);
                    }
                    subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                    subtasks.append(BuildCrossing(this, tile, network));
                    subtasks.append(RemoveExitsAndClean(this, tile, exitsToRemove));
                    col++;
                }
            }

            // opposite pairs: NE+SW and SE+NW
            local oppositePairs = [
                [Direction.NE, Direction.SW],
                [Direction.SE, Direction.NW],
            ];
            foreach (pair in oppositePairs) {
                local tile = AIMap.GetTileIndex(64 + col * 8, 64);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(RemoveExitsAndClean(this, tile, pair));
                col++;
            }

            // second row: same tests but with branch line exits
            col = 0;
            for (local numRemoved = 1; numRemoved <= 4; numRemoved++) {
                for (local rot = 0; rot < 4; rot++) {
                    local tile = AIMap.GetTileIndex(64 + col * 8, 72);
                    local exitsToRemove = [];
                    for (local i = 0; i < numRemoved; i++) {
                        exitsToRemove.append(allDirections[(rot + i) % 4]);
                    }
                    subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                    subtasks.append(BuildCrossing(this, tile, network));
                    subtasks.append(ConvertToBranchExits(this, tile, network));
                    subtasks.append(RemoveExitsAndClean(this, tile, exitsToRemove));
                    col++;
                }
            }

            // second row opposite pairs
            foreach (pair in oppositePairs) {
                local tile = AIMap.GetTileIndex(64 + col * 8, 72);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network));
                subtasks.append(RemoveExitsAndClean(this, tile, pair));
                col++;
            }

            // third row: mixed branch and normal exits
            // for each number of branch exits (1, 2, 3) x 4 rotations,
            // remove one branch exit and one normal exit
            col = 0;
            for (local numBranch = 1; numBranch <= 3; numBranch++) {
                for (local rot = 0; rot < 4; rot++) {
                    local branchDirs = [];
                    for (local i = 0; i < numBranch; i++) {
                        branchDirs.append(allDirections[(rot + i) % 4]);
                    }
                    local firstBranch = branchDirs[0];
                    local firstNormal = allDirections[(rot + numBranch) % 4];

                    // remove a branch exit
                    local tile = AIMap.GetTileIndex(64 + col * 8, 80);
                    subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                    subtasks.append(BuildCrossing(this, tile, network));
                    subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                    subtasks.append(RemoveExitsAndClean(this, tile, [firstBranch]));
                    col++;

                    // remove a normal exit
                    tile = AIMap.GetTileIndex(64 + col * 8, 80);
                    subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                    subtasks.append(BuildCrossing(this, tile, network));
                    subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                    subtasks.append(RemoveExitsAndClean(this, tile, [firstNormal]));
                    col++;
                }
            }
            // fourth row: opposite branch exits mixed with normal exits
            // branch NE+SW with normal SE+NW, and branch SE+NW with normal NE+SW
            col = 0;
            local oppositeBranchPairs = [
                [Direction.NE, Direction.SW],
                [Direction.SE, Direction.NW],
            ];
            foreach (branchDirs in oppositeBranchPairs) {
                local normalDirs = [];
                foreach (d in allDirections) {
                    local isBranch = false;
                    foreach (b in branchDirs) {
                        if (d == b) isBranch = true;
                    }
                    if (!isBranch) normalDirs.append(d);
                }

                // remove a branch exit
                local tile = AIMap.GetTileIndex(64 + col * 8, 88);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                subtasks.append(RemoveExitsAndClean(this, tile, [branchDirs[0]]));
                col++;

                // remove a normal exit
                tile = AIMap.GetTileIndex(64 + col * 8, 88);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                subtasks.append(RemoveExitsAndClean(this, tile, [normalDirs[0]]));
                col++;

                // remove both branch exits
                tile = AIMap.GetTileIndex(64 + col * 8, 88);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                subtasks.append(RemoveExitsAndClean(this, tile, branchDirs));
                col++;

                // remove both normal exits
                tile = AIMap.GetTileIndex(64 + col * 8, 88);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                subtasks.append(RemoveExitsAndClean(this, tile, normalDirs));
                col++;

                // remove one branch + one normal (adjacent)
                tile = AIMap.GetTileIndex(64 + col * 8, 88);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                subtasks.append(RemoveExitsAndClean(this, tile, [branchDirs[0], normalDirs[0]]));
                col++;

                // remove one branch + one normal (the other adjacent pair)
                tile = AIMap.GetTileIndex(64 + col * 8, 88);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                subtasks.append(RemoveExitsAndClean(this, tile, [branchDirs[0], normalDirs[1]]));
                col++;

                // remove three exits (keep one branch)
                tile = AIMap.GetTileIndex(64 + col * 8, 88);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                subtasks.append(RemoveExitsAndClean(this, tile, [branchDirs[1], normalDirs[0], normalDirs[1]]));
                col++;

                // remove three exits (keep one normal)
                tile = AIMap.GetTileIndex(64 + col * 8, 88);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, branchDirs));
                subtasks.append(RemoveExitsAndClean(this, tile, [branchDirs[0], branchDirs[1], normalDirs[0]]));
                col++;
            }
            // fifth row: sequential branch conversion then removal
            // reproduce: two normal exits, one branch exit, then a second
            // branch exit that is converted and subsequently cleaned up
            col = 0;
            for (local rot = 0; rot < 4; rot++) {
                local firstBranch = allDirections[(rot + 2) % 4];
                local removedBranch = allDirections[(rot + 1) % 4];

                local tile = AIMap.GetTileIndex(64 + col * 8, 96);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, [firstBranch]));
                subtasks.append(ConvertToBranchExits(this, tile, network, [removedBranch]));
                subtasks.append(RemoveExitsAndClean(this, tile, [removedBranch]));
                col++;
            }

            // same row: branch converted and cleaned up, THEN the other branch built
            // reproduce: SE converted to branch, SE cleaned up, then SW converted to branch
            for (local rot = 0; rot < 4; rot++) {
                local removedBranch = allDirections[(rot + 1) % 4];
                local secondBranch = allDirections[(rot + 2) % 4];

                local tile = AIMap.GetTileIndex(64 + col * 8, 96);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, [removedBranch]));
                subtasks.append(RemoveExitsAndClean(this, tile, [removedBranch]));
                subtasks.append(ConvertToBranchExits(this, tile, network, [secondBranch]));
                col++;
            }

            // same sequences but rotating the other way (counterclockwise)
            for (local rot = 0; rot < 4; rot++) {
                local firstBranch = allDirections[(rot + 2) % 4];
                local removedBranch = allDirections[(rot + 3) % 4];

                local tile = AIMap.GetTileIndex(64 + col * 8, 96);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, [firstBranch]));
                subtasks.append(ConvertToBranchExits(this, tile, network, [removedBranch]));
                subtasks.append(RemoveExitsAndClean(this, tile, [removedBranch]));
                col++;
            }

            for (local rot = 0; rot < 4; rot++) {
                local removedBranch = allDirections[(rot + 3) % 4];
                local secondBranch = allDirections[(rot + 2) % 4];

                local tile = AIMap.GetTileIndex(64 + col * 8, 96);
                subtasks.append(LevelTerrain(this, tile, Rotation.ROT_0, [0, 0], [Crossing.WIDTH-1, Crossing.WIDTH-1], false));
                subtasks.append(BuildCrossing(this, tile, network));
                subtasks.append(ConvertToBranchExits(this, tile, network, [removedBranch]));
                subtasks.append(RemoveExitsAndClean(this, tile, [removedBranch]));
                subtasks.append(ConvertToBranchExits(this, tile, network, [secondBranch]));
                col++;
            }
        }
        RunSubtasks();
    }

    function _tostring() {
        return "BuildAllCrossings";
    }
}

class ConvertToBranchExits extends Builder {
    network = null;
    crossingTile = null;
    directions = null;

    constructor(parentTask, location, network, directions = null) {
        Builder.constructor(parentTask, location);
        this.network = network;
        this.crossingTile = location;
        this.directions = directions != null ? directions : [Direction.NE, Direction.SE, Direction.SW, Direction.NW];
    }

    function Run() {
        foreach (direction in directions) {
            // reset to crossing origin before each direction
            SetLocalCoordinateSystem(crossingTile, Rotation.ROT_0);

            local rotation, offset;
            switch (direction) {
                case Direction.NE:
                    rotation = Rotation.ROT_0; offset = [0,0]; break;
                case Direction.SE:
                    rotation = Rotation.ROT_270; offset = [0,3]; break;
                case Direction.SW:
                    rotation = Rotation.ROT_180; offset = [3,3]; break;
                case Direction.NW:
                    rotation = Rotation.ROT_90; offset = [3,0]; break;
            }

            SetLocalCoordinateSystem(GetTile(offset), rotation);

            // four segments of track
            BuildSegment([1,1], [2,1]);
            BuildSegment([1,2], [2,2]);
            BuildSegment([1,1], [1,2]);
            BuildSegment([2,1], [2,2]);
            
            // outer diagonals (clockwise)
            BuildRail([1,0], [1,1], [0,1]);
            BuildRail([0,2], [1,2], [1,3]);
            BuildRail([3,2], [2,2], [2,3]);
            BuildRail([2,0], [2,1], [3,1]);
            
            // inner diagonals (clockwise)
            BuildRail([2,1], [1,1], [1,2]);
            BuildRail([1,1], [1,2], [2,2]);
            BuildRail([2,1], [2,2], [1,2]);
            BuildRail([1,1], [2,1], [2,2]);

            if (network.rightSide) {
                // the exit might have a waypoint
                Demolish([0,2]);

                RemoveRail([-1,2], [0,2], [1,2]);
                RemoveRail([1,3], [1,2], [0,2]);
                RemoveRail([2,2], [1,2], [0,2]);
                
                // allow left turn from the counter clockwise entrance to turn into the branch line if it still exists
                if (HasRail([2,0])) {
                    BuildRail([2,0], [2,1], [1,1]);
                }

                // left turn out of the branch line, or right turn into it from the two clockwise entrances
                BuildRail([1,2], [1,1], [0,1]);
                
                RemoveSignal([0,1], [-1, 1]);
                BuildSignal([0,1], [-1, 1], AIRail.SIGNALTYPE_PBS);
            } else {
                // the exit might have a waypoint
                Demolish([0,1]);

                RemoveRail([-1,1], [0,1], [1,1]);
                RemoveRail([1,0], [1,1], [0,1]);
                RemoveRail([2,1], [1,1], [0,1]);
                
                // allow right turn from the clockwise entrance to turn into the branch line if it still exists
                if (HasRail([2,3])) {
                    BuildRail([2,3], [2,2], [1,2]);
                }

                // right turn out of the branch line, or left turn into it from the two counter clockwise entrances
                BuildRail([1,1], [1,2], [0,2]);

                RemoveSignal([0,2], [-1, 2]);
                BuildSignal([0,2], [-1, 2], AIRail.SIGNALTYPE_PBS);
            }

            local crossing = Crossing(location);
            ExtendCrossing.RemoveDeadRails(crossing);
        }
    }

    function HasRail(tileCoords) {
        return AIRail.IsRailTile(GetTile(tileCoords));
    }

    function _tostring() {
        local s = "ConvertToBranchExits " + TileToString(crossingTile) + " ";
        foreach (i, d in directions) {
            if (i > 0) s += ",";
            s += DirectionName(d);
        }
        return s;
    }
}

class RemoveExitsAndClean extends Builder {
    exitsToRemove = null;

    constructor(parentTask, location, exitsToRemove) {
        Builder.constructor(parentTask, location);
        this.exitsToRemove = exitsToRemove;
    }

    function Run() {
        foreach (direction in exitsToRemove) {
            switch (direction) {
                case Direction.NE:
                    RemoveRail([-1,1], [0,1], [1,1]);
                    RemoveRail([-1,2], [0,2], [1,2]);
                    break;
                case Direction.SE:
                    RemoveRail([1,4], [1,3], [1,2]);
                    RemoveRail([2,4], [2,3], [2,2]);
                    break;
                case Direction.SW:
                    RemoveRail([4,1], [3,1], [2,1]);
                    RemoveRail([4,2], [3,2], [2,2]);
                    break;
                case Direction.NW:
                    RemoveRail([1,-1], [1,0], [1,1]);
                    RemoveRail([2,-1], [2,0], [2,1]);
                    break;
            }
        }

        local crossing = Crossing(location);
        ExtendCrossing.RemoveDeadRails(crossing);
    }

    function _tostring() {
        local s = "RemoveExitsAndClean " + TileToString(location) + " -";
        foreach (i, d in exitsToRemove) {
            if (i > 0) s += ",";
            s += DirectionName(d);
        }
        return s;
    }
}

class Halt extends Task {
    function Run() {
        Debug("Halting");
        while (true) {
            AIController.Sleep(365 * TICKS_PER_DAY);
        }
    }

    function _tostring() {
        return "Halt";
    }
}