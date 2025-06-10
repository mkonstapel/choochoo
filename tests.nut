class RunTests extends Task {
    constructor() {
        Task.constructor(null, [BuildTestNetwork(), Halt()]);
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