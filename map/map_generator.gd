extends Node
class_name MapGenerator

func generate_map_data(num_points: int, num_cities: int, map_size: Vector2) -> Dictionary:
    var points = _generate_random_points(num_points, map_size)
    var connections = _generate_connections(points)
    var cities = _place_cities(points, num_cities)

    return {
        "points": points,
        "connections": connections,
        "cities": cities
    }

func _generate_random_points(num_points: int, map_size: Vector2) -> Array[Vector2]:
    var points: Array[Vector2] = []
    for i in num_points:
        points.append(Vector2(randf_range(0, map_size.x), randf_range(0, map_size.y)))
    return points

func _generate_connections(points: Array[Vector2]) -> Array[Array]:
    var final_connections: Array[Array] = []

    if points.size() < 2:
        return final_connections
    
    if points.size() == 2:
        return [[0, 1]]

    var delaunay_edges = _get_delaunay_edges(points)

    # Now apply Prim's algorithm to ensure full connectivity
    var num_points = points.size()
    var mst_edges = _get_minimum_spanning_tree(points, delaunay_edges, num_points)
    
    return mst_edges

func _get_delaunay_edges(points: Array[Vector2]) -> Array[Array]:
    var edges: Array[Array] = []

    var triangles = Geometry2D.make_triangles_from_points(points)

    # Extract unique edges from triangles
    var unique_edges = {}
    for i in range(0, triangles.size(), 3):
        var p1_idx = triangles[i]
        var p2_idx = triangles[i+1]
        var p3_idx = triangles[i+2]

        _add_unique_edge(unique_edges, p1_idx, p2_idx)
        _add_unique_edge(unique_edges, p2_idx, p3_idx)
        _add_unique_edge(unique_edges, p3_idx, p1_idx)
    
    for edge_str in unique_edges:
        edges.append(JSON.parse_string(edge_str))
    
    return edges

func _add_unique_edge(unique_edges: Dictionary, idx1: int, idx2: int) -> void:
    var edge = [min(idx1, idx2), max(idx1, idx2)]
    unique_edges[str(edge)] = true

func _get_minimum_spanning_tree(points: Array[Vector2], initial_edges: Array[Array], num_points: int) -> Array[Array]:
    var mst_edges: Array[Array] = []
    var visited: Array = [0] * num_points # 0 for unvisited, 1 for visited
    visited[0] = 1 # Start with the first point
    var visited_count = 1

    # Use a dictionary to store all possible edges and their weights
    # Key: str([idx1, idx2]), Value: distance
    var all_edges: Dictionary = {}
    for edge in initial_edges:
        var p1_idx = edge[0]
        var p2_idx = edge[1]
        var dist = points[p1_idx].distance_to(points[p2_idx])
        all_edges[str([p1_idx, p2_idx])] = dist

    while visited_count < num_points:
        var min_dist = INF
        var best_edge = []

        # Iterate over all current edges to find the shortest one connecting visited to unvisited
        for edge_str in all_edges:
            var edge = JSON.parse_string(edge_str)
            var p1_idx = edge[0]
            var p2_idx = edge[1]
            var dist = all_edges[edge_str]

            if (visited[p1_idx] == 1 and visited[p2_idx] == 0) or \
               (visited[p1_idx] == 0 and visited[p2_idx] == 1):
                if dist < min_dist:
                    min_dist = dist
                    best_edge = edge
        
        if best_edge.is_empty():
            # This means there's an isolated cluster not connected by initial_edges.
            # This shouldn't happen with Delaunay + adding direct edges if necessary.
            # For now, let's break to prevent infinite loop, but this indicates an issue.
            # A robust solution might need to check if the graph is connected before MST.
            break

        mst_edges.append(best_edge)
        if visited[best_edge[0]] == 0:
            visited[best_edge[0]] = 1
            visited_count += 1
        if visited[best_edge[1]] == 0:
            visited[best_edge[1]] = 1
            visited_count += 1
            
        # Remove the edge to avoid re-evaluating it unnecessarily
        all_edges.erase(str(best_edge))
        all_edges.erase(str([best_edge[1], best_edge[0]])) # also erase reversed key

    # If not all points are connected by MST, add direct edges to ensure connectivity
    # This handles cases where Delaunay might not connect everything due to edge cases
    # Or when initial_edges is sparse.
    for i in range(num_points):
        if visited[i] == 0:
            # Find the closest already visited point and connect it
            var closest_dist = INF
            var closest_point_idx = -1
            for j in range(num_points):
                if visited[j] == 1:
                    var dist = points[i].distance_to(points[j])
                    if dist < closest_dist:
                        closest_dist = dist
                        closest_point_idx = j
            if closest_point_idx != -1:
                mst_edges.append([min(i, closest_point_idx), max(i, closest_point_idx)])
                visited[i] = 1
                visited_count += 1

    return mst_edges

    var triangles = Geometry2D.make_triangles_from_points(points)

    # Extract edges from triangles
    var edges = {}
    for i in range(0, triangles.size(), 3):
        var p1_idx = triangles[i]
        var p2_idx = triangles[i+1]
        var p3_idx = triangles[i+2]

        # Add edges, ensuring uniqueness and sorted order for key
        var edge1 = [min(p1_idx, p2_idx), max(p1_idx, p2_idx)]
        var edge2 = [min(p2_idx, p3_idx), max(p2_idx, p3_idx)]
        var edge3 = [min(p3_idx, p1_idx), max(p3_idx, p1_idx)]

        edges[str(edge1)] = true
        edges[str(edge2)] = true
        edges[str(edge3)] = true

    # Convert unique edges back to array of arrays
    for edge_str in edges:
        connections.append(JSON.parse_string(edge_str))

    

func _place_cities(points: Array[Vector2], num_cities: int) -> Array[Vector2]:
    # Placeholder for city placement logic
    # This will return an array of selected point locations for cities
    return points.shuffle().slice(0, num_cities)
