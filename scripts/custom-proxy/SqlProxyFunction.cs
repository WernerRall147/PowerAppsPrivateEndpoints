using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using System.Data.SqlClient;
using System.Collections.Generic;

namespace PowerPlatformProxy
{
    public static class SqlProxyFunction
    {
        [FunctionName("SqlQueryProxy")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            log.LogInformation("SQL Proxy function processed a request");

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic data = JsonConvert.DeserializeObject(requestBody);

            // Get the connection string and query from the request body
            string connectionString = data?.connectionString;
            string query = data?.query;
            
            if (string.IsNullOrEmpty(connectionString) || string.IsNullOrEmpty(query))
            {
                return new BadRequestObjectResult("Please provide connectionString and query in the request body");
            }

            try
            {
                // Execute query against the private SQL database
                var results = await ExecuteQueryAsync(connectionString, query);
                return new OkObjectResult(results);
            }
            catch (Exception ex)
            {
                log.LogError(ex, "Error executing SQL query");
                return new ObjectResult(new { error = ex.Message }) { StatusCode = 500 };
            }
        }

        private static async Task<List<Dictionary<string, object>>> ExecuteQueryAsync(string connectionString, string query)
        {
            var results = new List<Dictionary<string, object>>();

            using (SqlConnection connection = new SqlConnection(connectionString))
            {
                await connection.OpenAsync();

                using (SqlCommand command = new SqlCommand(query, connection))
                {
                    using (var reader = await command.ExecuteReaderAsync())
                    {
                        while (await reader.ReadAsync())
                        {
                            var row = new Dictionary<string, object>();
                            
                            for (int i = 0; i < reader.FieldCount; i++)
                            {
                                var columnName = reader.GetName(i);
                                var value = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                row.Add(columnName, value);
                            }
                            
                            results.Add(row);
                        }
                    }
                }
            }

            return results;
        }
    }
}
