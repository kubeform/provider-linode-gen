package main

import (
	"flag"
	"log"

	"kubeform.dev/generator-v2/util"

	"github.com/linode/terraform-provider-linode/linode"
)

func main() {
	apisPath := flag.String("apis-path", "<empty>", "path to generate the apis. Pass empty string to use default path <$GOPATH/kubeform.dev/provider-linode-api")
	controllerPath := flag.String("controller-path", "<empty>", "path to generate the controller. Pass empty string to use default path <$GOPATH/kubeform.dev/provider-linode-controller")
	flag.Parse()

	if *apisPath == "<empty>" {
		apisPath = nil
	}
	if *controllerPath == "<empty>" {
		controllerPath = nil
	}

	opts := &util.GeneratorOptions{
		ProviderName:       "linode",
		ProviderData:       linode.Provider(),
		ProviderImportPath: "github.com/linode/terraform-provider-linode/linode",
		Version:            "v1alpha1",
		APIsPath:           apisPath,
		ControllerPath:     controllerPath,
	}
	err := util.Generate(opts)
	if err != nil {
		log.Println(err.Error())
		return
	}
}
