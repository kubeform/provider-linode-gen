package main

import (
	"log"

	"github.com/linode/terraform-provider-linode/linode"
	"kubeform.dev/generator/util"
)

func main() {
	apisPath := ""
	controllerPath := ""
	opts := &util.GeneratorOptions{
		ProviderName:       "linode",
		ProviderData:       linode.Provider(),
		ProviderImportPath: "github.com/linode/terraform-provider-linode/linode",
		Version:            "v1alpha1",
		APIsPath:           &apisPath,
		ControllerPath:     &controllerPath,
	}
	err := util.Generate(opts)
	if err != nil {
		log.Println(err.Error())
		return
	}
}
