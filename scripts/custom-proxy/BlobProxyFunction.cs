using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using System.Collections.Generic;
using System.Linq;

namespace PowerPlatformProxy
{
    public static class BlobProxyFunction
    {
        [FunctionName("BlobListProxy")]
        public static async Task<IActionResult> ListBlobs(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = "blob/list")] HttpRequest req,
            ILogger log)
        {
            log.LogInformation("Blob List Proxy function processed a request");

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic data = JsonConvert.DeserializeObject(requestBody);

            // Get parameters from request body
            string connectionString = data?.connectionString;
            string containerName = data?.containerName;
            string prefix = data?.prefix ?? "";
            
            if (string.IsNullOrEmpty(connectionString) || string.IsNullOrEmpty(containerName))
            {
                return new BadRequestObjectResult("Please provide connectionString and containerName in the request body");
            }

            try
            {
                var blobServiceClient = new BlobServiceClient(connectionString);
                var containerClient = blobServiceClient.GetBlobContainerClient(containerName);

                var blobs = new List<object>();
                await foreach (var blobItem in containerClient.GetBlobsAsync(prefix: prefix))
                {
                    blobs.Add(new
                    {
                        name = blobItem.Name,
                        contentLength = blobItem.Properties.ContentLength,
                        contentType = blobItem.Properties.ContentType,
                        lastModified = blobItem.Properties.LastModified
                    });
                }

                return new OkObjectResult(blobs);
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Error listing blobs");
                return new ObjectResult(new { error = ex.Message }) { StatusCode = 500 };
            }
        }

        [FunctionName("BlobDownloadProxy")]
        public static async Task<IActionResult> DownloadBlob(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = "blob/download")] HttpRequest req,
            ILogger log)
        {
            log.LogInformation("Blob Download Proxy function processed a request");

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic data = JsonConvert.DeserializeObject(requestBody);

            // Get parameters from request body
            string connectionString = data?.connectionString;
            string containerName = data?.containerName;
            string blobName = data?.blobName;
            
            if (string.IsNullOrEmpty(connectionString) || string.IsNullOrEmpty(containerName) || string.IsNullOrEmpty(blobName))
            {
                return new BadRequestObjectResult("Please provide connectionString, containerName, and blobName in the request body");
            }

            try
            {
                var blobServiceClient = new BlobServiceClient(connectionString);
                var containerClient = blobServiceClient.GetBlobContainerClient(containerName);
                var blobClient = containerClient.GetBlobClient(blobName);

                if (!await blobClient.ExistsAsync())
                {
                    return new NotFoundObjectResult($"Blob '{blobName}' not found in container '{containerName}'");
                }

                var response = await blobClient.DownloadAsync();
                var content = await BinaryData.FromStreamAsync(response.Value.Content);
                
                // For small files, return as base64
                // For production, you might want to handle large files differently
                return new OkObjectResult(new { 
                    name = blobName,
                    contentType = response.Value.ContentType,
                    contentLength = response.Value.ContentLength,
                    content = Convert.ToBase64String(content.ToArray())
                });
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Error downloading blob");
                return new ObjectResult(new { error = ex.Message }) { StatusCode = 500 };
            }
        }

        [FunctionName("BlobUploadProxy")]
        public static async Task<IActionResult> UploadBlob(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = "blob/upload")] HttpRequest req,
            ILogger log)
        {
            log.LogInformation("Blob Upload Proxy function processed a request");

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic data = JsonConvert.DeserializeObject(requestBody);

            // Get parameters from request body
            string connectionString = data?.connectionString;
            string containerName = data?.containerName;
            string blobName = data?.blobName;
            string contentBase64 = data?.content;
            string contentType = data?.contentType ?? "application/octet-stream";
            
            if (string.IsNullOrEmpty(connectionString) || 
                string.IsNullOrEmpty(containerName) || 
                string.IsNullOrEmpty(blobName) ||
                string.IsNullOrEmpty(contentBase64))
            {
                return new BadRequestObjectResult("Please provide connectionString, containerName, blobName, and content (base64) in the request body");
            }

            try
            {
                var blobServiceClient = new BlobServiceClient(connectionString);
                var containerClient = blobServiceClient.GetBlobContainerClient(containerName);
                var blobClient = containerClient.GetBlobClient(blobName);

                byte[] contentBytes = Convert.FromBase64String(contentBase64);
                using (var stream = new MemoryStream(contentBytes))
                {
                    await blobClient.UploadAsync(stream, new BlobHttpHeaders { ContentType = contentType });
                }
                
                return new OkObjectResult(new { 
                    name = blobName, 
                    size = contentBytes.Length,
                    url = blobClient.Uri.ToString()
                });
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Error uploading blob");
                return new ObjectResult(new { error = ex.Message }) { StatusCode = 500 };
            }
        }
    }
}
