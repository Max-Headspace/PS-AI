function Remove-VectorStore {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('vector_store_id')]
        [Alias('VectorStore')]
        [ValidateScript({ [bool](Get-VectorStoreIdFromInputObject $_) })]
        [Object]$InputObject,

        [Parameter()]
        [int]$TimeoutSec = 0,

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$MaxRetryCount = 0,

        [Parameter()]
        [OpenAIApiType]$ApiType = [OpenAIApiType]::OpenAI,

        [Parameter()]
        [System.Uri]$ApiBase,

        [Parameter(DontShow)]
        [string]$ApiVersion,

        [Parameter()]
        [ValidateSet('openai', 'azure', 'azure_ad')]
        [string]$AuthType = 'openai',

        [Parameter()]
        [securestring][SecureStringTransformation()]$ApiKey,

        [Parameter()]
        [Alias('OrgId')]
        [string]$Organization,

        [Parameter()]
        [System.Collections.IDictionary]$AdditionalQuery,

        [Parameter()]
        [System.Collections.IDictionary]$AdditionalHeaders,

        [Parameter()]
        [object]$AdditionalBody
    )

    begin {
        # Initialize API Key
        [securestring]$SecureToken = Initialize-APIKey -ApiKey $ApiKey -ErrorAction Stop

        # Initialize API Base
        $ApiBase = Initialize-APIBase -ApiBase $ApiBase -ApiType $ApiType -ErrorAction Stop

        # Initialize Organization ID
        $Organization = Initialize-OrganizationID -OrgId $Organization

        # Get API context
        $OpenAIParameter = Get-OpenAIContext -EndpointName 'VectorStores' -ApiType $ApiType -AuthType $AuthType -ApiBase $ApiBase -ApiVersion $ApiVersion -ErrorAction Stop
    }

    process {
        # Get id
        [string][UrlEncodeTransformation()]$VsId = Get-VectorStoreIdFromInputObject $InputObject
        if (-not $VsId) {
            Write-Error -Exception ([System.ArgumentException]::new('Could not retrieve Vector Store ID.'))
            return
        }

        #region Construct Query URI
        $UriBuilder = [System.UriBuilder]::new($OpenAIParameter.Uri)
        $UriBuilder.Path += "/$VsId"
        $QueryUri = $UriBuilder.Uri
        #endregion

        #region Send API Request
        $params = @{
            Method            = 'Delete'
            Uri               = $QueryUri
            ContentType       = $OpenAIParameter.ContentType
            TimeoutSec        = $TimeoutSec
            MaxRetryCount     = $MaxRetryCount
            ApiKey            = $SecureToken
            AuthType          = $OpenAIParameter.AuthType
            Organization      = $Organization
            Headers           = @{'OpenAI-Beta' = 'assistants=v2' }
            AdditionalQuery   = $AdditionalQuery
            AdditionalHeaders = $AdditionalHeaders
            AdditionalBody    = $AdditionalBody
        }
        $Response = Invoke-OpenAIAPIRequest @params

        # error check
        if ($null -eq $Response) {
            return
        }
        #endregion

        #region Parse response object
        try {
            $Response = $Response | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Error -Exception $_.Exception
        }
        #endregion

        #region Verbose Output
        if ($Response.deleted) {
            Write-Verbose ('The vectore store with id "{0}" has been deleted.' -f $Response.id)
        }
        #endregion
    }

    end {

    }
}
