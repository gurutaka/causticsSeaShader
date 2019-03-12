using UnityEngine;

public class WaterSimulation : MonoBehaviour
{
    [SerializeField]
    CustomRenderTexture texture;

    void Start()
    {
        texture.Initialize();
    }

}