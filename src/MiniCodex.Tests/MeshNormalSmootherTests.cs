using System;
using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Render.Rendering;
using Xunit;

namespace MiniCodex.Tests;

public class MeshNormalSmootherTests
{
    [Fact]
    public void Smooth_AveragesNormalsForWeldedVertices()
    {
        var geometry = new MeshGeometry
        {
            Vertices = new[]
            {
                new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(0, 1, 0),
                new Vector3(1, 0, 0), new Vector3(1, 1, 0), new Vector3(0, 1, 0)
            },
            VertexNormals = new[]
            {
                new Vector3(0, 0, 1), new Vector3(0, 0, 1), new Vector3(0, 0, 1),
                new Vector3(0, 0, 2), new Vector3(0, 0, 2), new Vector3(0, 0, 2)
            },
            Indices = new[] { 0, 1, 2, 3, 4, 5 }
        };

        MeshNormalSmoother.Smooth(geometry, minTriangles: 2);

        foreach (var n in geometry.VertexNormals)
        {
            Assert.Equal(0f, n.X);
            Assert.Equal(0f, n.Y);
            Assert.Equal(1f, n.Z);
        }
    }

    [Fact]
    public void Smooth_DoesNotAffectLowPolyWhenGateEnabled()
    {
        var geometry = new MeshGeometry
        {
            Vertices = new[] { new Vector3(0,0,0), new Vector3(1,0,0), new Vector3(0,1,0) },
            VertexNormals = new[] { new Vector3(0,0,1), new Vector3(0,0,1), new Vector3(0,0,1) },
            Indices = new[] { 0, 1, 2 }
        };

        MeshNormalSmoother.Smooth(geometry, minTriangles: 500_000);

        Assert.Equal(new Vector3(0,0,1), geometry.VertexNormals[0]);
    }
}