/**
 * Tile math.
 */

DIRECTION_X = Tile(1, 0);
DIRECTION_Y = Tile(0, 1);

/**
 * A tile, in some arbitrary X, Y local coordinate system.
 */
class Tile {

	x = null;
	y = null;
	
	constructor(x, y) {
		this.x = x;
		this.y = y;
	}
	
	function GetTiles() {
		return this;
	}
}

/**
 * A tile and a direction.
 */
class Vector {
	
	position = null;
	direction = null;
	
	constructor(position, direction) {
		this.position <- position;
		this.direction <- direction;	
	}
	
	function GetTiles() {
		return [position, Tile(position.x + direction.x, position.y + direction.y)];
	}

}

/**
 * A number of tiles in a row.
 */
class Strip {
	
	tile = null;
	length = null;
	direction = null;
	
	constructor(vector, length) {
		this.tile = vector.position;
		this.direction = vector.direction;
		this.length = length;
	}
	
	/**
	 * Extend the strip from its start.
	 */
	function ExtendHead(amount) {
		tile = new Tile(tile.x - direction.x * amount, tile.y - direction.y * amount);
		length += amount;
	}
	
	/**
	 * Extend the strip from its end.
	 */
	function ExtendTail(amount) {
		length += amount;
	}
	
	function GetTiles() {
		local tiles = [];
		for (local i = 0; i < length; i++) {
			tiles.append(Tile(tile.x + direction.x * i, tile.y + direction.y * i));
		}
		
		return tiles;
	}
}

/**
 * Convert "abstract" tiles to AITiles, relative to an origin AITile.
 */
function ToAITile(origin, tile) {
	return AIMap.GetTileIndex(AIMap.GetTileX(origin) + tile.x,AIMap.GetTileY(origin) + tile.y);
}
	
function ToAITiles(origin, tiles) {
	local aiTiles = [];
	foreach (tile in tiles) {
		aiTiles.append(ToAITile(origin, tile));
	}
	
	return aiTiles;
}
