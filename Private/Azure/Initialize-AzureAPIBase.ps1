function Initialize-AzureAPIBase {
    [CmdletBinding()]
    [OutputType([System.Uri])]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [System.Uri]$ApiBase,

        [Parameter()]
        [bool]$SearchGlobal = $true,

        [Parameter()]
        [bool]$SearchEnv = $true
    )

    [System.Uri]$Result = $null

    if ($null -ne $ApiBase) {
        $Result = $ApiBase
    }
    # Search API base below priorities.
    #   1. Global variable "OPENAI_API_BASE"
    elseif ($SearchGlobal -and $null -ne $global:OPENAI_API_BASE -and $global:OPENAI_API_BASE -as [uri]) {
        $Result = [uri]$global:OPENAI_API_BASE
    }
    #   2. Environment variable "OPENAI_API_BASE"
    elseif ($SearchEnv -and $null -ne $env:OPENAI_API_BASE -and $env:OPENAI_API_BASE -as [uri]) {
        $Result = [uri]$env:OPENAI_API_BASE
    }

    if ($null -eq $Result) {
        Write-Error -Exception ([System.ArgumentException]::new('Please specify your Azure OpenAI Endpoint to "ApiBase" parameter.'))
        return
    }
    else {
        $Result
    }
}
